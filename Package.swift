// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Wavefront",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Wavefront",
            targets: ["Wavefront"]
        ),
    ],
    dependencies: [
        // AMSMB2 for SMB2/3 network share access
        // Using branch reference to allow unsafe flags from libsmb2
        .package(url: "https://github.com/amosavian/AMSMB2.git", from: "3.1.0"),
        // YouTubeKit for native YouTube stream extraction
        .package(url: "https://github.com/alexeichhorn/YouTubeKit.git", from: "0.4.0")
    ],
    targets: [
        .target(
            name: "Wavefront",
            dependencies: [
                .product(name: "AMSMB2", package: "AMSMB2"),
                .product(name: "YouTubeKit", package: "YouTubeKit")
            ],
            path: "Sources/Wavefront"
        ),
        .testTarget(
            name: "WavefrontTests",
            dependencies: ["Wavefront"],
            path: "Tests/WavefrontTests"
        ),
    ]
)

// NOTE: AMSMB2 License
// AMSMB2 wraps libsmb2 which is LGPL v2.1
// For App Store distribution, link AMSMB2 dynamically
