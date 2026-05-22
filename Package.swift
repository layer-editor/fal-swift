// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FalClient",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "FalClient",
            targets: ["FalClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nnabeyang/swift-msgpack.git", from: "0.3.3"),
    ],
    targets: [
        .target(
            name: "FalClient",
            dependencies: [
                .product(name: "SwiftMsgpack", package: "swift-msgpack"),
            ],
            path: "Sources/FalClient"
        ),
        .testTarget(
            name: "FalClientTests",
            dependencies: [
                "FalClient",
            ],
            path: "Tests/FalClientTests"
        ),
    ]
)
