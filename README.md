<br/>

<p align="left"><img src="https://cloud.githubusercontent.com/assets/1567433/13918338/f8670eea-ef7f-11e5-814d-f15bdfd6b2c0.png" height="180"/>

# FetchImage

`FetchImage` is a Swift package that makes it easy to download images using [`Nuke`](https://github.com/kean/Nuke) and display them in SwiftUI apps. This particular fork comes bundled with support for [Google Firebase](https://github.com/firebase/firebase-ios-sdk) `StorageReferences`.

> **Note**. This is an API preview. It is not battle-tested yet, and might change in the future.

## Usage
Here is an example of using `FetchImage` in a custom SwiftUI view.

```swift
public struct ImageView: View {
    let url: URL

    @StateObject private var image = FetchImage()

    public var body: some View {
        ZStack {
            Rectangle().fill(Color.gray)
            image.view?
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        }

        // Cancel and restart the request during scrolling
        // If the view is still on screen, use `cancel()` instead of `reset()`.
        .onAppear {
            // Ensure that synchronous cache lookup doesn't trigger animations
            withoutAnimation {
                image.load(url)
            }
        }
        .onDisappear(perform: image.reset)

        // (Optional) Animate image appearance
        .animation(.default)
    }
}

private func withoutAnimation(_ closure: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, closure)
}
```
> For iOS 13, use `@ObservedObject`. 
> WARNING: `@ObservedObject` does own the instance, you need to maintain the strong references to the `FetchImage` instances somewhere else.

### Lists
`FetchImage` may also be used in a `List`:

```swift
struct DetailsView: View {
    @State var refresh: Bool = false

    var body: some View {
        List(imageUrls, id: \.self) {
            ImageView(url: $0)
                .frame(height: 200)
        }
    }
}
```

### Priority
`FetchImage` gives you full control over how to manage the download and how to display the image. For example, one thing that you could do is to replace `onAppear` and `onDisappear` hooks to lower the priority of the requests instead of cancelling them. This might be useful if you want to continue loading and caching the images even if the user leaves the screen, but you still want the images the are currently on screen to be downloaded first.

```swift
.onAppear {
    self.image.priority = .normal
    self.image.fetch() // Restart the request if previous download failed
}
.onDisappear {
    self.image.priority = .low
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

## Overview

`FetchImage` is a state object, `StateObject` (use `ObservableObject` on iOS 13) that allows you to manage the download of a single image and observe the results of the download. All of the changes to the download state are published using properties marked with `@Published` property wrapper.

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

    public struct Progress {
        /// The number of bytes that the task has received.
        public internal(set) var completed: Int64 = 0

        /// A best-guess upper bound on the number of bytes the client expects to send.
        public internal(set) var total: Int64 = 0
    }

    /// The progress of the image download.
    @Published public var progress = Progress()
}
```

You can initialize the download with a `URL`, or an `ImageRequest`, just as you would expect with `Nuke`. `FetchImage` supports everything that `Nuke` does. This includes changing request priorities, progressive image decoding, and more.

```swift
public final class FetchImage: ObservableObject, Identifiable {
    /// Initializes the fetch request and immediately start loading.
    public init(request: ImageRequest, pipeline: ImagePipeline = .shared)

    /// Initializes the fetch request and immediately start loading.
    public convenience init(url: URL, pipeline: ImagePipeline = .shared)
}
```

When the `FetchImage` object is created, it automatically starts the request. You also have an option to `cancel` the request and restart it later using `fetch` method. This is something that you would typically need when displaying images in a `List`. You can also use `fetch` to restart failed downloads.

Another little thing that `FetchImage` does for you is automatically cancelling the download when de-instantiated.

```swift
public final class FetchImage: ObservableObject, Identifiable {

    /// Updates the priority of the task, even if the task is already running.
    public var priority: ImageRequest.Priority

    /// Starts loading an image unless the download is already completed successfully.
    public func fetch()

    /// Marks the request as being cancelled.
    public func cancel()
}
```

### Low Data Mode

iOS 13 introduced a new [Low Data mode](https://support.apple.com/en-us/HT210596) and `FetchImage` offers a built-in support for it.

```swift
FetchImage(regularUrl: highQualityUrl, lowDataUrl: lowQualityUrl)
```

`FetchedImage.init(regularUrl:lowDataUrl:pipeline:)` is a convenience initializer that fetches the image with a regular URL with constrained network access disabled, and if the download fails because of the constrained network access, uses a low data URL instead. It also handles the scenarios like fetching a high quality image when unconstrained network access is restored.

# Requirements

| Nuke          | Swift           | Xcode           | Platforms                                         |
|---------------|-----------------|-----------------|---------------------------------------------------|
| FetchImage     | Swift 5.3       | Xcode 12      | iOS 13.0 / watchOS 6.0 / macOS 10.15 / tvOS 13.0  |

# License

FetchImage is available under the MIT license. See the LICENSE file for more info.
