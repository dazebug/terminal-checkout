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
        // `exclude` and not `resources`: SwiftPM notices any `.lproj` under a target and, left to
        // itself, demands `defaultLocalization` and starts producing a `Bundle.module` accessor —
        // the machinery D1 rejected, because that accessor resolves through an absolute `.build`
        // path on the machine that compiled it and so hides a missing copy exactly where it would
        // be caught. `app/build.sh` copies these into `Contents/Resources/` and the app reads them
        // with `Bundle(path:)`; this line is what keeps the two schemes from overlapping.
        .executableTarget(name: "App", dependencies: ["Core"], exclude: ["Resources"]),
        .executableTarget(name: "Relay", dependencies: ["Core"]),
        .executableTarget(name: "WarpHelper", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "AppTests", dependencies: ["App", "Core"]),
    ]
)
