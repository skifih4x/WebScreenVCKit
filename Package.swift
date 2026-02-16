// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WebScreenVCKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "WebScreenVCKit",
            targets: ["WebScreenVCKit"]
        )
    ],
    targets: [
        .target(
            name: "WebScreenVCKit",
            path: "WebScreenVCKit",
            exclude: ["WebScreenVCKit.docc"]
        )
    ]
)
