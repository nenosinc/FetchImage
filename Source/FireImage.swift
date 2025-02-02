//
//  FireImage.swift
//  FetchImage
//
//  Created by Sam Spencer on 7/11/21.
//  Copyright © 2022 Sam Spencer
//

import Combine
import Firebase
import FirebaseStorage
import Foundation
import Nuke
import SwiftUI

public enum FireImageError: Error {
    case sourceEmpty
}

/// An observable object that simplifies image loading in SwiftUI.
///
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
public final class FireImage: ObservableObject, Identifiable {
    
    /// Returns the current fetch result.
    ///
    @Published public private(set) var result: Result<ImageResponse, Error>?
    
    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    ///
    public var image: PlatformImage? { imageContainer?.image }
    
    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    ///
    @Published public private(set) var imageContainer: ImageContainer?
    
    /// Returns `true` if the image is being loaded.
    ///
    @Published public private(set) var isLoading: Bool = false
    
    /// Animations to be used when displaying the loaded images. By default, `nil`.
    ///
    /// - note: Animation isn't used when image is available in memory cache.
    ///
    public var animation: Animation?
    
    /// The download progress.
    ///
    public struct Progress: Equatable {
        /// The number of bytes that the task has received.
        ///
        public let completed: Int64
        
        /// A best-guess upper bound on the number of bytes the client expects to send.
        ///
        public let total: Int64
    }
    
    /// The progress of the image download.
    ///
    @Published public private(set) var progress = Progress(completed: 0, total: 0)
    
    /// Updates the priority of the task, even if the task is already running.
    /// `nil` by default.
    ///
    public var priority: ImageRequest.Priority? {
        didSet { priority.map { imageTask?.priority = $0 } }
    }
    
    /// Gets called when the request is started.
    ///
    public var onStart: ((_ task: ImageTask) -> Void)?
    
    /// Gets called when the request progress is updated.
    ///
    public var onProgress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?
    
    /// Gets called when the requests finished successfully.
    ///
    public var onSuccess: ((_ response: ImageResponse) -> Void)?
    
    /// Gets called when the requests fails.
    ///
    public var onFailure: ((_ response: Error) -> Void)?
    
    /// Gets called when the request is completed.
    ///
    public var onCompletion: ((_ result: Result<ImageResponse, Error>) -> Void)?
    
    public var pipeline: ImagePipeline = .shared
    
    /// Image processors to be applied unless the processors are provided in the request.
    /// `nil` by default.
    ///
    public var processors: [ImageProcessing]?
    
    private var imageTask: ImageTask?
    
    // MARK: - Publisher Support
    
    private var lastResponse: ImageResponse?
    private var cancellable: AnyCancellable?
    
    // MARK: - Lifecycle
    
    deinit {
        cancel()
    }
    
    public init() {}
    
    // MARK: Load
    
    public typealias CompletedLoad = ((URL?) async -> Void)
    public typealias UniqueURL = (() async throws -> URL)
    
    /// Initializes the fetch request with a Firebase `StorageReference` to an image in
    /// any of Nuke's supported formats. The remote URL is then fetched from Firebase
    /// and the image is subsequently fetched as well.
    ///
    /// - parameter regularStorageRef: A `StorageReference` which points to a
    ///   Firebase Storage file in any of Nuke's supported image formats.
    /// - parameter uniqueURL: A caller to request any potentially cached image URLs.
    ///   Implementing your own URL caching prevents potentially unnecessary roundtrips to
    ///   your Firebase Storage bucket.
    /// - parameter finished: Called when URL loading has completed and fetching can
    ///   begin. If the caller is `nil`, a fetch operation is queued immediately.
    ///
    public func load(_ regularStorageRef: StorageReference, uniqueURL: UniqueURL?, finished: CompletedLoad?) async {
        // If provided, query the uniqueURL block for a cached URL.
        // If successful, use that parameter instead.
        if let uniqueURLBlock = uniqueURL {
            do {
                let givenURL = try await uniqueURLBlock()
                let newRequest = ImageRequest(url: givenURL)
                priority = newRequest.priority
                await finishOrLoad(newRequest, discoveredURL: givenURL, finish: finished)
                
                // Return early, no need to awaken the Firebeasty
                return
            } catch let error {
                print("Unable to load cached URL. \(error)")
            }
        }
        
        await fetchStandardURL(for: regularStorageRef, finish: finished)
    }
    
    private func finishOrLoad(_ request: ImageRequest, discoveredURL: URL? = nil, finish: CompletedLoad?) async {
        if let completionBlock = finish {
            await completionBlock(discoveredURL)
        }
        
        await load(request)
    }
    
    private func fetchStandardURL(for regularStorageRef: StorageReference, finish: CompletedLoad?) async {
        do {
            let discoveredURL = try await regularStorageRef.downloadURL()
            let newRequest = ImageRequest(url: discoveredURL)
            priority = newRequest.priority
            await finishOrLoad(newRequest, discoveredURL: discoveredURL, finish: finish)
        } catch let error {
            print("Unable to fetch remote URL: \(error)")
            await finish?(nil)
        }
    }
    
    /// Loads an image with the given request.
    ///
    @MainActor public func load(_ request: ImageRequestConvertible?) {
        reset()
        
        guard var request = request?.asImageRequest() else {
            handle(result: .failure(FireImageError.sourceEmpty), isSync: true)
            return
        }
        
        if let processors = self.processors, !processors.isEmpty && request.processors.isEmpty {
            request.processors = processors
        }
        if let priority = self.priority {
            request.priority = priority
        }
        
        // Quick synchronous memory cache lookup
        if let image = pipeline.cache[request] {
            if image.isPreview {
                imageContainer = image // Display progressive image
            } else {
                let response = ImageResponse(container: image, request: request, cacheType: .disk)
                handle(result: .success(response), isSync: true)
                return
            }
        }
        
        isLoading = true
        progress = Progress(completed: 0, total: 0)
        
        let task = pipeline.loadImage(
            with: request,
            progress: { [weak self] response, completed, total in
                guard let self = self else { return }
                self.progress = Progress(completed: completed, total: total)
                if let response = response {
                    withAnimation(self.animation) {
                        self.handle(preview: response)
                    }
                }
                self.onProgress?(response, completed, total)
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                withAnimation(self.animation) {
                    self.handle(result: result.mapError { $0 }, isSync: false)
                }
            }
        )
        imageTask = task
        onStart?(task)
    }
    
    /// Display progressively decoded image.
    /// 
    private func handle(preview: ImageResponse) {
        self.imageContainer = preview.container
    }
    
    private func handle(result: Result<ImageResponse, Error>, isSync: Bool) {
        isLoading = false
        
        if case .success(let response) = result {
            self.imageContainer = response.container
        }
        self.result = result
        
        imageTask = nil
        switch result {
        case .success(let response): onSuccess?(response)
        case .failure(let error): onFailure?(error)
        }
        onCompletion?(result)
    }
    
    // MARK: Load (Publisher)
    
    /// Loads an image with the given publisher.
    ///
    /// - warning: Some `FetchImage` features, such as progress reporting and
    /// dynamically changing the request priority, are not available when
    /// working with a publisher.
    ///
    public func load<P: Publisher>(_ publisher: P) where P.Output == ImageResponse {
        reset()
        
        // Not using `first()` because it should support progressive decoding
        isLoading = true
        cancellable = publisher.sink(receiveCompletion: { [weak self] completion in
            guard let self = self else { return }
            self.isLoading = false
            switch completion {
            case .finished:
                if let response = self.lastResponse {
                    self.result = .success(response)
                } // else was cancelled, do nothing
            case .failure(let error):
                self.result = .failure(error)
            }
        }, receiveValue: { [weak self] response in
            guard let self = self else { return }
            self.lastResponse = response
            self.imageContainer = response.container
        })
    }
    
    // MARK: Cancel
    
    /// Marks the request as being cancelled. Continues to display a downloaded
    /// image.
    ///
    public func cancel() {
        // pipeline-based
        imageTask?.cancel() // Guarantees that no more callbacks are will be delivered
        imageTask = nil
        
        // publisher-based
        cancellable = nil
        
        // common
        if isLoading { isLoading = false }
    }
    
    /// Resets the `FetchImage` instance by cancelling the request and removing
    /// all of the state including the loaded image.
    ///
    public func reset() {
        cancel()
        
        // Avoid publishing unchanged values
        if isLoading { isLoading = false }
        if imageContainer != nil { imageContainer = nil }
        if result != nil { result = nil }
        lastResponse = nil // publisher-only
        if progress != Progress(completed: 0, total: 0) { progress = Progress(completed: 0, total: 0) }
    }
    
    // MARK: View
    
    public var view: SwiftUI.Image? {
        #if os(macOS)
        return image.map(Image.init(nsImage:))
        #else
        return image.map(Image.init(uiImage:))
        #endif
    }
    
}
