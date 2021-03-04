// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "FetchImage",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(name: "FetchImage", targets: ["FetchImage"])
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", from: "9.2.0"),
        .package(name: "Firebase", url: "https://github.com/firebase/firebase-ios-sdk.git", from: "7.3.0")
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
