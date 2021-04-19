//
// The MIT License (MIT)
//
// Copyright (c) 2021 Alexander Grebenyuk (github.com/kean).
//

import SwiftUI
import Nuke
import FirebaseStorage

public final class PrefetchViewModel: ObservableObject, ScrollViewPrefetcherDelegate {
    
    private let imagePrefetcher: ImagePrefetcher
    private let scrollViewPrefetcer: ScrollViewPrefetcher
    public private(set) var urls: [URL]
    
    public init() {
        imagePrefetcher = ImagePrefetcher()
        scrollViewPrefetcer = ScrollViewPrefetcher()
        urls = []
        scrollViewPrefetcer.delegate = self
    }
    
    public func load(photoURLs: [URL]) {
        urls = photoURLs
        scrollViewPrefetcer.scheduleRefreshIfNeeded()
    }
    
    public func load(photoReferences: [StorageReference], uniqueURL: @escaping (StorageReference) -> URL?) {
        let loadTask = DispatchGroup()
        let totalRefs = photoReferences.count
        var currentRef: Int = 1
        
        for ref in photoReferences {
            if currentRef == 1 {
                loadTask.enter()
            }
            
            if let cachedURL = uniqueURL(ref) {
                urls.append(cachedURL)
                
                currentRef = currentRef + 1
                if currentRef >= totalRefs {
                    loadTask.leave()
                }
                continue
            } else {
                DispatchQueue.global(qos: .userInitiated).async {
                    ref.downloadURL { (foundURL, thrownError) in
                        if let safeFoundURL = foundURL {
                            self.urls.append(safeFoundURL)
                            currentRef = currentRef + 1
                        } else {
                            if let safeError = thrownError {
                                print("[PrefetchViewModel] Unable to fetch download URL for photo. \(safeError)")
                                currentRef = currentRef + 1
                            }
                        }
                        
                        if currentRef >= totalRefs {
                            loadTask.leave()
                        }
                    }
                }
            }
        }
        
        loadTask.notify(queue: DispatchQueue.main) {
            self.scrollViewPrefetcer.scheduleRefreshIfNeeded()
        }
    }
    
    public func onAppear(_ index: Int) {
        scrollViewPrefetcer.onAppear(index)
    }
    
    public func onDisappear(_ index: Int) {
        scrollViewPrefetcer.onDisappear(index)
    }
    
    
    // MARK: ScrollViewPrefetcherDelegate
    
    public func getAllIndicesForPrefetcher(_ prefetcher: ScrollViewPrefetcher) -> Range<Int> {
        urls.indices // The prefetcher needs to know which indices are valid
    }
    
    public func prefetcher(_ prefetcher: ScrollViewPrefetcher, prefetchItemsAt indices: [Int]) {
        imagePrefetcher.startPrefetching(with: indices.map( { urls[$0] }))
    }
    
    public func prefetcher(_ prefetcher: ScrollViewPrefetcher, cancelPrefechingForItemAt indices: [Int]) {
        imagePrefetcher.stopPrefetching(with: indices.map { urls[$0] })
    }
    
}
