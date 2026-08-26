import Foundation

public let cmuxWorkspaceCreateMethod = "workspace.create"
public let cmuxSurfaceSendTextMethod = "surface.send_text"
public let cmuxSurfaceReadTextMethod = "surface.read_text"
public let cmuxDebugTerminalsMethod = "debug.terminals"

/// The facts the App target may render about cmux. Core deliberately carries no user-facing text;
/// the App boundary maps these cases to the current catalogue when the setup window draws.
public enum CmuxSocketStatus: Equatable {
    case notInstalled
    case notRunning
    case denied
    case reachable
    case failed(String)
}

/// Classifies one live `cmux ping` observation. A successful PONG or an access denial wins over
/// the default socket path because the CLI discovers sockets through `CMUX_SOCKET_PATH` and
/// `/tmp/cmux-last-socket-path`; only a missing default socket with neither result means stopped.
public func classifyCmuxSocketStatus(
    socketExists: Bool, pingStatus: Int32, stdout: String, stderr: String
) -> CmuxSocketStatus {
    let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    if pingStatus == 0, output.contains("PONG") { return .reachable }
    if output.localizedCaseInsensitiveContains("access denied") { return .denied }
    if !socketExists { return .notRunning }

    let summary = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return .failed(summary.isEmpty ? "exit status \(pingStatus)" : summary)
}

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

enum CmuxRecovery: Equatable {
    case rethrow
    case launchAndRetry
}

enum CmuxReadiness: Equatable {
    case ready
    case denied
    case notReady
}

/// A successful lightweight RPC is the readiness answer; a socket denial is an immediate
/// diagnosis, and any other failure means that the server is not ready yet.
func cmuxReadinessOutcome(from error: TerminalError?) -> CmuxReadiness {
    guard let error else { return .ready }
    if case .cmuxSocketDenied = error { return .denied }
    return .notReady
}

/// A workspace denial is a configuration diagnosis, not a launch failure: opening cmux cannot
/// change a running instance's socket mode. Retrying is safe only when the request is proven not
/// to have reached the server; `workspace.create` is not idempotent, so timeouts, malformed
/// responses, and post-create failures are rethrown because the server may already have created a
/// workspace. The measured stopped-cmux CLI emits `Error: Failed to connect to socket at <path>
/// (Connection refused, errno 61)` for a stale socket, so the classifier below is anchored to
/// the CLI's measured connection prefix rather than searching substrings. That anchor is tied to
/// the measured cmux CLI version; unknown failures are conservatively rethrown instead of guessed
/// to be connection failures.
func cmuxRecoveryAction(
    afterFirstFailure: TerminalError, launchAttempted: Bool
) -> CmuxRecovery {
    switch afterFirstFailure {
    case .cmuxNotReachable(_):
        return launchAttempted ? .rethrow : .launchAndRetry
    default:
        return .rethrow
    }
}

/// The cmux CLI emitted these measured stderr forms:
/// `Error: Failed to connect to socket at /tmp/…/dead.sock (Connection refused, errno 61)` means
/// the socket file exists but its listener is gone after cmux stopped; `Error: Socket not found at
/// /tmp/…/nonexistent.sock` means the socket file is absent. The `Error: ` prefix is part of the
/// CLI output and is required: if a future CLI stops emitting it, this classifier fails closed and
/// rethrows rather than treating an unmeasured string as proof that no request reached the server.
/// An earlier test omitted that prefix and passed while blocking the real auto-launch path. These
/// anchors are tied to the measured cmux CLI version; anchoring prevents `workspace.create:
/// post-create hook: no such file or directory` from authorizing a duplicate workspace retry just
/// because of a substring match.
func classifyCmuxCLIFailure(_ message: String) -> TerminalError {
    if message.hasPrefix("Error: Failed to connect to socket at ")
        || message.hasPrefix("Error: Socket not found at ") {
        return .cmuxNotReachable(message)
    }

    return .cmuxRPCFailed(message)
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

/// The workspace request deliberately leaves window selection and cwd to cmux. The server's
/// default is the user's last active window, while the command's `{cd}` clause owns the cwd.
public func cmuxWorkspaceCreateParameters() -> [String: Any] {
    ["focus": true]
}

/// The identifiers returned by `workspace.create` are both required to address the new surface.
/// A missing surface is not a successful workspace creation for this caller: without it no
/// command can be sent.
public func cmuxWorkspaceIdentifiers(
    from response: [String: Any]
) -> (workspaceID: String, surfaceID: String)? {
    guard let workspaceID = response["workspace_id"] as? String, !workspaceID.isEmpty,
          let surfaceID = response["surface_id"] as? String, !surfaceID.isEmpty else {
        return nil
    }
    return (workspaceID, surfaceID)
}

public func cmuxSurfaceSendTextParameters(surfaceID: String, text: String) -> [String: Any] {
    ["surface_id": surfaceID, "text": text]
}

public func cmuxSurfaceReadTextParameters(surfaceID: String) -> [String: Any] {
    ["surface_id": surfaceID]
}

public func cmuxScreenText(from response: [String: Any]) -> String? {
    response["text"] as? String
}

public func cmuxRPCFailure(method: String, status: Int32, stderr: String) -> TerminalError {
    let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    if status != 0 && detail.localizedCaseInsensitiveContains("access denied") {
        return .cmuxSocketDenied
    }
    let message = detail.isEmpty ? "exit status " + String(status) : detail
    let classified = classifyCmuxCLIFailure(message)
    if case .cmuxNotReachable(_) = classified { return classified }
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
