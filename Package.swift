// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "FetchImage",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "FetchImage", targets: ["FetchImage"])
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Nuke.git", from: "11.3.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.0.0")
    ],
    targets: [
        .target(
            name: "FetchImage",
            dependencies: [
                "Nuke",
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk")
            ],
            path: "Source")
    ]
)
