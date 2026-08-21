// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TerminalCheckout",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TerminalCheckout", targets: ["App"]),
        .executable(name: "terminal-checkout-relay", targets: ["Relay"]),
        // Warp pane 안에서 도는 주입 헬퍼 — TIOCSTI는 호출 프로세스의 제어 터미널로만
        // 허용되므로 앱이 아니라 pane 안의 프로세스가 claude 입력을 넣는다
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
