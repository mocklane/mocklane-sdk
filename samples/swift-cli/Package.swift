// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mocklane-swift-sample",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../packages/swift"),
    ],
    targets: [
        .executableTarget(
            name: "MocklaneSwiftSample",
            dependencies: [
                .product(name: "Mocklane", package: "swift"),
            ],
            path: "Sources"
        ),
    ]
)
