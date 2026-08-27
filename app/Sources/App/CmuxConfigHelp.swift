import Foundation

enum CmuxConfigRevealTarget: Equatable {
    case file(URL)
    case directory(URL)
    case nothing
}

/// The setup card's non-destructive cmux configuration help.
enum CmuxConfigHelp {
    static func defaultConfigURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("cmux", isDirectory: true)
            .appendingPathComponent("cmux.json")
    }

    static func cmuxConfigClipboardFragment() -> String {
        "\"automation\": { \"socketControlMode\": \"automation\" }"
    }

    static func cmuxConfigRevealTarget(
        configURL: URL, fileExists: Bool, directoryExists: Bool
    ) -> CmuxConfigRevealTarget {
        if fileExists { return .file(configURL) }
        if directoryExists { return .directory(configURL.deletingLastPathComponent()) }
        return .nothing
    }
}
