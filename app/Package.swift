// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TerminalCheckout",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TerminalCheckout", targets: ["App"]),
        .executable(name: "terminal-checkout-relay", targets: ["Relay"]),
    ],
    targets: [
        .target(name: "Core"),
        .executableTarget(name: "App", dependencies: ["Core"]),
        .executableTarget(name: "Relay", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
