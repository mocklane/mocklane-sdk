// swift-tools-version: 5.9
import PackageDescription

// Distribution manifest for Swift Package Manager.
//
// SPM resolves a package by git URL only when Package.swift sits at the
// repository root, so this manifest exposes the Swift package that lives in
// packages/swift. The nested manifest there remains the source of truth for
// package-local development (`cd packages/swift && swift test`).
//
// Consumers:
//   .package(url: "https://github.com/mocklane/mocklane-sdk.git", from: "0.1.1")
let package = Package(
    name: "Mocklane",
    platforms: [.macOS(.v13), .iOS(.v15)],
    products: [
        .library(name: "Mocklane", targets: ["Mocklane"]),
    ],
    targets: [
        .target(
            name: "Mocklane",
            path: "packages/swift/Sources/Mocklane"
        ),
        .testTarget(
            name: "MocklaneTests",
            dependencies: ["Mocklane"],
            path: "packages/swift/Tests/MocklaneTests",
            resources: [
                .copy("Resources/url-rewrite.json"),
            ]
        ),
    ]
)
