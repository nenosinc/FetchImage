// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "FetchImage",
    platforms: [
        .iOS("15.0"),
        .macOS("12.0")
    ],
    products: [
        .library(name: "FetchImage", targets: ["FetchImage"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/kean/Nuke.git",
            .upToNextMajor(from: "10.4.0")
        ),
        .package(
            name: "Firebase",
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            .upToNextMajor(from: "8.9.0")
        )
    ],
    targets: [
        .target(name: "FetchImage",
                dependencies: [
                    "Nuke",
                    .product(name: "FirebaseStorageSwift-Beta", package: "Firebase")
                ],
                path: "Source")
    ]
)
