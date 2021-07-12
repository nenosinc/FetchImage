// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "FetchImage",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .tvOS(.v14),
        .watchOS(.v7)
    ],
    products: [
        .library(name: "FetchImage", targets: ["FetchImage"])
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", from: "10.3.1"),
        .package(name: "Firebase", url: "https://github.com/firebase/firebase-ios-sdk.git", from: "8.3.0")
    ],
    targets: [
        .target(name: "FetchImage",
                dependencies: [
                    "Nuke",
                    .product(name: "FirebaseStorage", package: "Firebase")
                ],
                path: "Source")
    ]
)
