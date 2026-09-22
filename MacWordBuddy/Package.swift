// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WordBuddyMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WordBuddyMac",
            path: "Sources/WordBuddyMac"
        ),
        .testTarget(
            name: "WordBuddyMacTests",
            dependencies: ["WordBuddyMac"],
            path: "Tests/WordBuddyMacTests"
        )
    ]
)
