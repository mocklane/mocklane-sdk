// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Mocklane",
    platforms: [.macOS(.v13), .iOS(.v15)],
    products: [
        .library(name: "Mocklane", targets: ["Mocklane"]),
    ],
    targets: [
        .target(name: "Mocklane"),
        .testTarget(
            name: "MocklaneTests",
            dependencies: ["Mocklane"],
            resources: [
                .copy("Resources/url-rewrite.json"),
            ]
        ),
    ]
)
