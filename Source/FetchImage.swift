//
// The MIT License (MIT)
//
// Copyright (c) 2020 Alexander Grebenyuk (github.com/kean).
//

import SwiftUI
import Nuke
import FirebaseStorage

/// Fetch a remote image and progressively load using cached resources first, if
/// available, then displaying a placeholder until fully loaded.
///
public final class FetchImage: ObservableObject, Identifiable {
    
    // MARK: - Paramaters
    
    /// The original request.
    ///
    public private(set) var request: ImageRequest?

    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    ///
    @Published public private(set) var image: PlatformImage? {
        didSet {
            DispatchQueue.global(qos: .userInitiated).async {
                if let uiImage = self.image?.imageWithoutBaseline() {
                    uiImage.getColors(quality: .high) { uiImageColors in
                        guard let foundColors = uiImageColors else { return }
                        Thread.executeOnMain {
                            self.imageColors = ImageColors(from: foundColors)
                        }
                    }
                }
            }
        }
    }
    
    /// Returns an error if the previous attempt to fetch the image failed with an
    /// error. Error is cleared out when the download is restarted.
    ///
    @Published public private(set) var error: Error?
    
    public struct Progress {
        /// The number of bytes that the task has received.
        ///
        public let completed: Int64
        
        /// A best-guess upper bound on the number of bytes the client expects to send.
        ///
        public let total: Int64
    }
    
    /// The progress of the image download.
    ///
    @Published public var progress = Progress(completed: 0, total: 0)
    
    /// Suggested background, accent, and foreground colors based on the loaded image.
    ///
    @Published public var imageColors: ImageColors?
    
    /// Updates the priority of the task, even if the task is already running.
    ///
    public var priority: ImageRequest.Priority = .normal {
        didSet { task?.priority = priority }
    }
    
    public var pipeline: ImagePipeline = .shared
    private var task: ImageTask?
    
    
    // MARK: - Lifecycle
    
    deinit {
        cancel()
    }

    public init() {}

    public func load(_ url: URL) {
        self.load(ImageRequest(url: url))
    }
    
    /// Initializes the fetch request with a Firebase Storage Reference to an image in
    /// any of Nuke's supported formats. The remote URL is then fetched from Firebase
    /// and the image is subsequently fetched as well.
    ///
    /// - parameter regularStorageRef: A `StorageReference` which points to a
    ///     Firebase Storage file in any of Nuke's supported image formats.
    /// - parameter uniqueURL: A caller to request any potentially cached image URLs.
    ///     Implementing your own URL caching prevents potentially unnecessary roundtrips to
    ///     your Firebase Storage bucket.
    /// - parameter finished: Called when URL loading has completed and fetching can
    ///     begin. If the caller is `nil`, a fetch operation is queued immediately.
    ///
    public func load(regularStorageRef: StorageReference, uniqueURL: (() -> URL?)? = nil, finished: ((URL?) -> Void)? = nil) {
        func finishOrLoad(_ request: ImageRequest, discoveredURL: URL? = nil) {
            if let completionBlock = finished {
                completionBlock(discoveredURL)
            }
            load(request)
        }
        
        func getRegularURL() {
            DispatchQueue.global(qos: .userInteractive).async {
                regularStorageRef.downloadURL { (discoveredURL, error) in
                    if let given = discoveredURL {
                        let newRequest = ImageRequest(url: given)
                        self.request = newRequest
                        self.priority = newRequest.priority
                        
                        finishOrLoad(newRequest, discoveredURL: given)
                    } else {
                        finished?(discoveredURL)
                    }
                }
            }
        }
        
        // If provided, query the uniqueURL block for a cached URL.
        // If successful, use that parameter instead.
        if let uniqueURLBlock = uniqueURL {
            if let givenURL = uniqueURLBlock() {
                // An existing unique URL where the image may be found or cached.
                let newRequest = ImageRequest(url: givenURL)
                self.request = newRequest
                self.priority = newRequest.priority
                finishOrLoad(newRequest, discoveredURL: givenURL)
                return // Return early, no need to awaken the Firebeasty
            }
        }
        
        getRegularURL()
    }
    
    // MARK: - Fetching
    
    /// Starts loading the image if not already loaded and the download is not already
    /// in progress.
    ///
    public func load(_ request: ImageRequest) {
        _reset()
        
        // Cancel previous task after starting a new one to make sure that if
        // there is an existing task already running we don't cancel it and start
        // a new once.
        let previousTask = self.task
        defer { previousTask?.cancel() }
        
        self.request = request
        
        // Try to display the regular image if it is available in memory cache
        if let container = pipeline.cachedImage(for: request) {
            Thread.executeOnMain {
                self.image = container.image
            }
            return // Nothing to do
        }
        
        _load(request: request)
    }

    private func _load(request: ImageRequest) {
        Thread.executeOnMain {
            self.progress = Progress(completed: 0, total: 0)
        }
        
        task = pipeline.loadImage(
            with: request,
            progress: { response, completed, total in
                Thread.executeOnMain {
                    self.progress = Progress(completed: completed, total: total)
                }
                
                if let image = response?.image {
                    Thread.executeOnMain {
                        self.image = image // Display progressively decoded image
                    }
                }
            },
            completion: { result in
                self.didFinishRequest(result: result)
            }
        )
        
        if priority != request.priority {
            task?.priority = priority
        }
    }

    private func didFinishRequest(result: Result<ImageResponse, ImagePipeline.Error>) {
        defer {
            task = nil
        }
        
        switch result {
        case let .success(response):
            Thread.executeOnMain {
                self.image = response.image
            }
        case let .failure(error):
            Thread.executeOnMain {
                self.error = error
            }
        }
    }
    
    
    // MARK: - State
    
    /// Marks the request as being cancelled. Continues to display a downloaded image.
    ///
    public func cancel() {
        task?.cancel() // Guarantees that no more callbacks are will be delivered
        task = nil
    }
    
    /// Resets the `FetchImage` instance by cancelling the request and removing all of
    /// the state including the loaded image.
    ///
    public func reset() {
        cancel()
        _reset()
    }

    private func _reset() {
        Thread.executeOnMain {
            self.image = nil
            self.error = nil
            self.progress = Progress(completed: 0, total: 0)
        }
        request = nil
    }
    
}

public extension FetchImage {
    
    var view: SwiftUI.Image? {
        #if os(macOS)
        return image.map(Image.init(nsImage:))
        #else
        return image.map(Image.init(uiImage:))
        #endif
    }
    
}

fileprivate extension Thread {
    
    class func executeOnMain(_ mainBlock: @escaping () -> Void) {
        if Thread.isMainThread == true {
            mainBlock()
        } else {
            DispatchQueue.main.async {
                mainBlock()
            }
        }
    }
    
}
