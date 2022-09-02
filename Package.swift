// swift-tools-version:5.6

/*
 * Maraca Swift Package for iOS
 */

import PackageDescription

let package = Package(
    name: "Maraca",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "Maraca",
            targets: [
                "Maraca"
            ]
        )
    ],
    dependencies: [
        // Socket Mobile - CaptureSDK
        .package(url: "https://github.com/SocketMobile/swift-package-capturesdk", .exact("1.5.2"))
    ],
    targets: [
        .target(
            name: "Maraca",
            dependencies: [
                .product(name: "CaptureSDK", package: "swift-package-capturesdk")
            ],
            path: "Sources/Maraca"
        )
    ]
)
