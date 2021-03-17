// The MIT License (MIT)
//
// Copyright (c) 2020 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import Nuke
import FirebaseStorage

/// Fetch a remote image and progressively load using cached resources first, if
/// available, then displaying a placeholder until fully loaded.
///
/// - warning: This is an API preview. It is not battle-tested yet and might
/// signficantly change in the future.
///
public final class FetchImage: ObservableObject, Identifiable {
    
    // MARK: - Paramaters
    
    /// The original request.
    public private(set) var request: ImageRequest? {
        didSet {
            assert(Thread.isMainThread, "Only modify the request from the main thread.")
            if currentlyLoadingImageQuality == .regular {
                cancel()
            }
            guard let newRequest = request else {
                if loadedImageQuality == .regular {
                    image = nil
                }
                return
            }
            priority = newRequest.priority
        }
    }
    
    /// The request to be performed if the original request fails with
    /// `networkUnavailableReason` `.constrained` (low data mode).
    public private(set) var lowDataRequest: ImageRequest? {
        didSet {
            assert(Thread.isMainThread, "Only modify the request from the main thread.")
            if currentlyLoadingImageQuality == .low {
                cancel()
            }
            if lowDataRequest == nil && loadedImageQuality == .low {
                image = nil
            }
        }
    }
    
    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    @Published public private(set) var image: PlatformImage?
    
    /// Returns an error if the previous attempt to fetch the image failed with an
    /// error. Error is cleared out when the download is restarted.
    @Published public private(set) var error: Error?
    
    /// Returns `true` if the image is being loaded.
    @Published public private(set) var isLoading: Bool = false
    
    public struct Progress {
        /// The number of bytes that the task has received.
        public let completed: Int64
        
        /// A best-guess upper bound on the number of bytes the client expects to send.
        public let total: Int64
    }
    
    /// The progress of the image download.
    @Published public var progress = Progress(completed: 0, total: 0)
    
    /// Updates the priority of the task, even if the task is already running.
    public var priority: ImageRequest.Priority = .normal {
        didSet { task?.priority = priority }
    }
    
    public var pipeline: ImagePipeline = .shared
    private var task: ImageTask?
    private var loadedImageQuality: ImageQuality?
    private var currentlyLoadingImageQuality: ImageQuality? = nil
    
    private enum ImageQuality {
        case regular
        case low
    }
    
    
    // MARK: - Lifecycle
    
    deinit {
        cancel()
    }
    
    public init() {
        
    }
    
    /// Loads an image with a regular URL and an optional low-data URL.
    ///
    /// If supplying an optional low-data URL, disables constrained network access on
    /// the full size request. If the download fails on the initial full size URL, falls
    /// back to the low-data URL.
    ///
    /// - parameter url: The remote image URL
    /// - parameter lowDataUrl: The low data remote image URL
    ///
    public func load(_ url: URL, lowDataUrl: URL? = nil) {
        var request = URLRequest(url: url)
        if let constrainedURL = lowDataUrl {
            request.allowsConstrainedNetworkAccess = false
            load(ImageRequest(urlRequest: request), lowDataRequest: ImageRequest(url: constrainedURL))
        } else {
            load(ImageRequest(url: url))
        }
    }
    
    /// Initializes the fetch request with a Firebase Storage Reference to an image in
    /// any of Nuke's supported formats. The remote URL is then fetched from Firebase
    /// and the image is subsequently fetched as well.
    ///
    /// - parameter regularStorageRef: A `StorageReference` which points to a
    ///     Firebase Storage file in any of Nuke's supported image formats.
    /// - parameter lowDataStorageRef: A `StorageReference` which points to a smaller
    ///     Firebase Storage file in any of Nuke's supported image formats, which is also
    ///     appropriate for low-data scenarios.
    /// - parameter uniqueURL: A caller to request any potentially cached image URLs.
    ///     Implementing your own URL caching prevents potentially unnecessary roundtrips to
    ///     your Firebase Storage bucket.
    /// - parameter finished: Called when URL loading has completed and fetching can
    ///     begin. If the caller is `nil`, a fetch operation is queued immediately.
    ///
    public func load(regularStorageRef: StorageReference, lowDataStorageRef: StorageReference? = nil,
                     uniqueURL: (() -> URL?)? = nil, finished: ((URL?) -> Void)? = nil) {
        func finishOrLoad(_ request: ImageRequest, lowDataRequest: ImageRequest? = nil, discoveredURL: URL? = nil) {
            if let completionBlock = finished {
                completionBlock(discoveredURL)
            } else {
                load(request)
            }
        }
        
        func getRegularURL(lowDataRequest: ImageRequest? = nil) {
            regularStorageRef.downloadURL { (discoveredURL, error) in
                if let given = discoveredURL {
                    let newRequest = ImageRequest(url: given)
                    self.request = newRequest
                    self.priority = newRequest.priority
                    
                    finishOrLoad(newRequest, lowDataRequest: lowDataRequest, discoveredURL: given)
                } else {
                    finished?(discoveredURL)
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
        
        if let lowDataRef = lowDataStorageRef {
            lowDataRef.downloadURL { (discoveredURL, error) in
                if let given = discoveredURL {
                    let constrainedRequest = ImageRequest(url: given)
                    self.lowDataRequest = constrainedRequest
                    getRegularURL(lowDataRequest: constrainedRequest)
                } else {
                    getRegularURL()
                }
            }
        } else {
            getRegularURL()
        }
    }
    
    
    // MARK: - Fetching
    
    /// Starts loading the image if not already loaded and the download is not already
    /// in progress.
    ///
    /// - note: Low Data Mode. If the `lowDataRequest` is provided and the regular
    /// request fails because of the constrained network access, the fetcher tries to
    /// download the low-quality image. The fetcher always tries to get the high quality
    /// image. If the first attempt fails, the next time you call `fetch`, it is going
    /// to attempt to fetch the regular quality image again.
    ///
    public func load(_ request: ImageRequest, lowDataRequest: ImageRequest? = nil) {
        _reset()
        
        // Cancel previous task after starting a new one to make sure that if
        // there is an existing task already running we don't cancel it and start
        // a new once.
        let previousTask = self.task
        defer { previousTask?.cancel() }
        
        self.request = request
        self.lowDataRequest = lowDataRequest
        
        // Try to display the regular image if it is available in memory cache
        if let container = pipeline.cachedImage(for: request) {
            (image, loadedImageQuality) = (container.image, .regular)
            return // Nothing to do
        }
        
        // Try to display the low data image and retry loading the regular image
        if let container = lowDataRequest.flatMap(pipeline.cachedImage(for:)) {
            (image, loadedImageQuality) = (container.image, .low)
        }
        
        isLoading = true
        load(request: request, quality: .regular)
    }
    
    private func load(request: ImageRequest, quality: ImageQuality) {
        progress = Progress(completed: 0, total: 0)
        currentlyLoadingImageQuality = quality
        
        task = pipeline.loadImage(
            with: request,
            progress: { [weak self] response, completed, total in
                guard let self = self else { return }
                
                self.progress = Progress(completed: completed, total: total)
                
                if let image = response?.image {
                    self.image = image // Display progressively decoded image
                }
            },
            completion: { [weak self] in
                self?.didFinishRequest(result: $0, quality: quality)
            }
        )
        
        if priority != request.priority {
            task?.priority = priority
        }
    }
    
    private func didFinishRequest(result: Result<ImageResponse, ImagePipeline.Error>, quality: ImageQuality) {
        task = nil
        currentlyLoadingImageQuality = nil
        
        switch result {
        case let .success(response):
            isLoading = false
            (image, loadedImageQuality) = (response.image, quality)
        case let .failure(error):
            // If the regular request fails because of the low data mode,
            // use an alternative source.
            if quality == .regular, error.isConstrainedNetwork, let request = self.lowDataRequest {
                if loadedImageQuality == .low {
                    isLoading = false // Low-quality image already loaded
                } else {
                    load(request: request, quality: .low)
                }
            } else {
                self.error = error
                isLoading = false
            }
        }
    }
    
    
    // MARK: - State
    
    /// Marks the request as being cancelled. Continues to display a downloaded image.
    ///
    public func cancel() {
        task?.cancel() // Guarantees that no more callbacks are will be delivered
        task = nil
        isLoading = false
    }
    
    /// Resets the `FetchImage` instance by cancelling the request and removing all of
    /// the state including the loaded image.
    ///
    public func reset() {
        cancel()
        _reset()
    }
    
    private func _reset() {
        isLoading = false
        image = nil
        error = nil
        progress = Progress(completed: 0, total: 0)
        loadedImageQuality = nil
    }
    
}

private extension ImagePipeline.Error {
    
    var isConstrainedNetwork: Bool {
        if case let .dataLoadingFailed(error) = self,
           (error as? URLError)?.networkUnavailableReason == .constrained {
            return true
        }
        return false
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
