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
    
    public init(photoURLs: [URL]) {
        self.imagePrefetcher = ImagePrefetcher()
        self.scrollViewPrefetcer = ScrollViewPrefetcher()
        self.urls = photoURLs
        
        self.scrollViewPrefetcer.delegate = self
    }
    
    public init(photoReferences: [StorageReference], uniqueURL: @escaping (StorageReference) -> URL?) {
        self.imagePrefetcher = ImagePrefetcher()
        self.scrollViewPrefetcer = ScrollViewPrefetcher()
        self.urls = []
        self.scrollViewPrefetcer.delegate = self
        
        for ref in photoReferences {
            if let cachedURL = uniqueURL(ref) {
                self.urls.append(cachedURL)
                continue
            } else {
                DispatchQueue.global(qos: .userInitiated).async {
                    ref.downloadURL { (foundURL, thrownError) in
                        if let safeFoundURL = foundURL {
                            self.urls.append(safeFoundURL)
                        } else {
                            if let safeError = thrownError {
                                print("[PrefetchViewModel] Unable to fetch download URL for photo. \(safeError)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    func onAppear(_ index: Int) {
        scrollViewPrefetcer.onAppear(index)
    }
    
    func onDisappear(_ index: Int) {
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
