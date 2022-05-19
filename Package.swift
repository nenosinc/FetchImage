// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "FetchImage",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "FetchImage", targets: ["FetchImage"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/kean/Nuke.git",
            .upToNextMajor(from: "10.9.0")
        ),
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            .upToNextMajor(from: "9.0.0")
        )
    ],
    targets: [
        .target(name: "FetchImage",
                dependencies: [
                    "Nuke",
                    .product(name: "FirebaseStorage", package: "firebase-ios-sdk")
                ],
                path: "Source")
    ]
)
