// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sip",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sip",
            path: "Sources/Sip"
        ),
        .testTarget(
            name: "SipTests",
            dependencies: ["Sip"],
            path: "Tests/SipTests"
        ),
    ]
)
