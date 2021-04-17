<br/>

<img alr="fetchimage library logo" src="https://user-images.githubusercontent.com/1567433/110703387-b6c58000-81c1-11eb-806d-8f9d97dc5ecd.png">

<p align="left">
<img src="https://img.shields.io/badge/platforms-iOS%2C%20macOS%2C%20watchOS%2C%20tvOS-lightgrey.svg">
</p>

`FetchImage` makes it easy to download images using [Nuke](https://github.com/kean/Nuke) and display them in SwiftUI apps.

## Overview

`FetchImage` is an observable object ([`ObservableObject`](https://developer.apple.com/documentation/combine/observableobject)) that allows you to manage the download of an image and observe the results of the download.

```swift
public final class FetchImage: ObservableObject, Identifiable {
    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    @Published public private(set) var image: PlatformImage?

    /// Returns an error if the previous attempt to fetch the most recent attempt
    /// to load the image failed with an error.
    @Published public private(set) var error: Error?

    /// Returns `true` if the image is being loaded.
    @Published public private(set) var isLoading: Bool = false

    /// The progress of the image download.
    @Published public var progress = Progress()
}
```

## Usage

`FetchImage` doesn't ship an image view because it's trivial to create one using SwiftUI and customize it precisely the way you want. 

```swift
struct ImageView: View {
    let url: URL

    @StateObject private var image = FetchImage()

    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray)
            image.view?
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        }
        .onAppear { image.load(url) }
        .onDisappear(perform: image.reset)
    }
}
```

> For iOS 13, use `@ObservedObject`. Keep in mind that `@ObservedObject` does not own the instance; you need to maintain a strong reference to the `FetchImage` instance.

### Lists

```swift
struct DetailsView: View {
    var body: some View {
        List(imageUrls, id: \.self) {
            ImageView(url: $0)
                .frame(height: 200)
        }
    }
}
```

> If the URL changes, add `.id(url)` to your `ImageView`. This will ensure that `onAppear` is called when the URL changes.

### Appearance

`FetchImage` gives you full control over how to manage the download and display the image. For example, if you want the download to continue when the view leaves the screen, change the appearance callbacks:

```swift
.onAppear {
    image.priority = .normal
    image.load(url)
}
.onDisappear {
    image.priority = .low
}
```

### Animations

```swift
struct ImageView: View {
    let url: URL

    @StateObject private var image = FetchImage()

    var body: some View {
        // ... create image view 
        .onAppear {
            // Ensure that memory cache lookup is performed without animations
            withoutAnimation {
                image.load(url)
            }
        }
        .onDisappear(perform: image.reset)
        .animation(.default)
    }
}

private func withoutAnimation(_ closure: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, closure)
}
```

### Firebase
You may also initialize a `FetchImage` using a Firestore `StorageReference`. These references can be easily created synchronously, but require an asynchronous call in order generate URLs for fetching the requested content. Unfortunately, this makes image loading in SwiftUI rather difficult. Using `Nuke` and `Firebase` together simplifies the whole process quite a bit:

```swift
@State referencedImage: StorageReference

public var body: some View {
    ImageView(image: FetchImage(regularStorageRef: referencedImage)
        .animation(.default)
}
```

# Requirements

| Nuke          | Swift           | Xcode           | Platforms                                         |
|---------------|-----------------|-----------------|---------------------------------------------------|
| FetchImage     | Swift 5.1       | Xcode 11.3      | iOS 13.0 / watchOS 6.0 / macOS 10.15 / tvOS 13.0  |

# License

FetchImage is available under the MIT license. See the LICENSE file for more info.
