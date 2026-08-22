// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TerminalCheckout",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TerminalCheckout", targets: ["App"]),
        .executable(name: "terminal-checkout-relay", targets: ["Relay"]),
        // The injection helper that runs inside a Warp pane — TIOCSTI is only allowed on the calling process's controlling terminal, so claude input is put in by a process inside the pane rather than by the app
        .executable(name: "terminal-checkout-warp-helper", targets: ["WarpHelper"]),
    ],
    targets: [
        .target(name: "Core"),
        .executableTarget(name: "App", dependencies: ["Core"]),
        .executableTarget(name: "Relay", dependencies: ["Core"]),
        .executableTarget(name: "WarpHelper", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "AppTests", dependencies: ["App", "Core"]),
    ]
)
