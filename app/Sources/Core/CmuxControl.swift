import Foundation

public let cmuxWorkspaceCreateMethod = "workspace.create"
public let cmuxSurfaceSendTextMethod = "surface.send_text"
public let cmuxSurfaceSendKeyMethod = "surface.send_key"
public let cmuxSurfaceReadTextMethod = "surface.read_text"
public let cmuxDebugTerminalsMethod = "debug.terminals"

public enum CmuxRPCError: Error, Equatable, CustomStringConvertible {
    case invalidParameters
    case invalidResponse

    public var description: String {
        switch self {
        case .invalidParameters: return "invalid JSON parameters"
        case .invalidResponse: return "invalid JSON response"
        }
    }
}

/// The explicit locations are first because the app's PATH is normally only `/usr/bin:/bin`.
/// The cmux bundle's resource executable is the canonical installation, followed by the two
/// conventional standalone locations and then the user's PATH.
public func cmuxCLICandidatePaths(
    homeDirectory: String = NSHomeDirectory(), path: String? = ProcessInfo.processInfo.environment["PATH"]
) -> [String] {
    var candidates = [
        "/Applications/cmux.app/Contents/Resources/bin/cmux",
        (homeDirectory as NSString).appendingPathComponent(
            "Applications/cmux.app/Contents/Resources/bin/cmux"
        ),
        "/opt/homebrew/bin/cmux",
        "/usr/local/bin/cmux",
    ]

    if let path {
        candidates += path.split(separator: ":", omittingEmptySubsequences: true).map {
            (String($0) as NSString).appendingPathComponent("cmux")
        }
    }
    return candidates
}

public func findCmuxCLI(
    homeDirectory: String = NSHomeDirectory(), path: String? = ProcessInfo.processInfo.environment["PATH"],
    isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
) -> String? {
    cmuxCLICandidatePaths(homeDirectory: homeDirectory, path: path).first(where: isExecutable)
}

/// cmux discovers its own socket. This helper only answers whether the default socket says that
/// cmux is alive; its result is deliberately not passed as an argument to the CLI.
public func cmuxSocketPath(
    homeDirectory: String = NSHomeDirectory(),
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> String? {
    let path = (homeDirectory as NSString).appendingPathComponent(".local/state/cmux/cmux.sock")
    return fileExists(path) ? path : nil
}

private func asciiJSON(_ data: Data) -> String {
    let source = String(decoding: data, as: UTF8.self)
    var result = String()
    result.reserveCapacity(source.utf8.count)

    for scalar in source.unicodeScalars {
        let value = scalar.value
        if value <= 0x7F {
            result.unicodeScalars.append(scalar)
        } else if value <= 0xFFFF {
            result += String(format: "\\u%04X", value)
        } else {
            let adjusted = value - 0x10000
            let high = 0xD800 + (adjusted >> 10)
            let low = 0xDC00 + (adjusted & 0x3FF)
            result += String(format: "\\u%04X\\u%04X", high, low)
        }
    }
    return result
}

public func cmuxRPCRequestJSON(method: String, params: [String: Any]) throws -> String {
    guard method.unicodeScalars.allSatisfy(\.isASCII), JSONSerialization.isValidJSONObject(params) else {
        throw CmuxRPCError.invalidParameters
    }
    let data: Data
    do {
        data = try JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])
    } catch {
        throw CmuxRPCError.invalidParameters
    }
    return asciiJSON(data)
}

public func cmuxRPCArguments(method: String, params: [String: Any]) throws -> [String] {
    ["rpc", method, try cmuxRPCRequestJSON(method: method, params: params)]
}

public func cmuxRPCResponse(_ data: Data) throws -> [String: Any] {
    guard
        let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
        let response = object as? [String: Any]
    else {
        throw CmuxRPCError.invalidResponse
    }

    // Some CLI versions wrap a successful result while the current response is the object itself.
    // Keep the fields the caller asked for at the same level in either form.
    if response.count == 1, let result = response["result"] as? [String: Any] {
        return result
    }
    return response
}

public func cmuxRPCFailure(method: String, status: Int32, stderr: String) -> TerminalError {
    let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if status != 0 && detail.localizedCaseInsensitiveContains("access denied") {
        return .cmuxSocketDenied
    }
    let message = detail.isEmpty ? "exit status " + String(status) : detail
    return .cmuxRPCFailed("\(method): \(message)")
}

/// Runs one cmux RPC. The JSON argument is ASCII-only, so Foundation cannot NFD-reencode the
/// user's text while launching the child process.
@discardableResult
public func cmuxRPC(
    cli: String, method: String, params: [String: Any] = [:], timeout: TimeInterval = 10
) throws -> [String: Any] {
    let arguments: [String]
    do {
        arguments = try cmuxRPCArguments(method: method, params: params)
    } catch let error as CmuxRPCError {
        throw TerminalError.cmuxRPCFailed("\(method): \(error.description)")
    }

    let result: (status: Int32, stdout: String, stderr: String)
    do {
        result = try runProcess(cli, arguments, timeout: timeout)
    } catch let error as TerminalError {
        throw error
    } catch {
        throw TerminalError.cmuxRPCFailed("\(method): \(error.localizedDescription)")
    }

    guard result.status == 0 else {
        throw cmuxRPCFailure(
            method: method, status: result.status, stderr: result.stderr + result.stdout
        )
    }

    do {
        return try cmuxRPCResponse(Data(result.stdout.utf8))
    } catch let error as CmuxRPCError {
        throw TerminalError.cmuxRPCFailed("\(method): \(error.description)")
    }
}
