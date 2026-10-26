// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "photolib_video",
    platforms: [.iOS("16.0"), .macOS("13.0")],
    products: [.library(name: "photolib-video", targets: ["photolib_video"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "photolib_video",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
        )
    ]
)
