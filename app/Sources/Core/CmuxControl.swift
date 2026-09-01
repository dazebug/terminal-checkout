import Foundation

public let cmuxWorkspaceCreateMethod = "workspace.create"
public let cmuxWorkspaceListMethod = "workspace.list"
public let cmuxPaneListMethod = "pane.list"
public let cmuxSurfaceListMethod = "surface.list"
public let cmuxSurfaceSplitMethod = "surface.split"
public let cmuxSurfaceCreateMethod = "surface.create"
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
/// the socket-existence hint because a CLI may still reach a server through discovery; only a
/// missing resolved socket with neither result means stopped.
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

/// A cmux release channel. Stable and NIGHTLY are separate app bundles running from one codebase:
/// each server records its live socket in two pointer files, with the state-directory copy read
/// before the `/tmp` copy. Both binaries carry all four channel file names — stable, nightly, dev,
/// staging — measured with `strings` on 0.64.22 and 0.64.22-nightly. An unpinned CLI
/// "auto-discovers tagged/debug sockets" beyond its channel file, and with both servers running
/// that discovery reached across channels (nightly CLI answered PONG while only its stable sibling
/// was assumed up), so a live pointer pins `CMUX_SOCKET_PATH` and a missing selected-channel
/// pointer never permits a cross-channel discovery.
public enum CmuxChannel: CaseIterable, Equatable {
    case stable
    case nightly

    public var bundleID: String {
        switch self {
        case .stable: return "com.cmuxterm.app"
        case .nightly: return "com.cmuxterm.app.nightly"
        }
    }

    /// The pointer file the channel's server rewrites on every start. The stable channel's file
    /// is the unprefixed name; a restart can change the socket's own basename (`cmux.sock` →
    /// `cmux-501.sock`, observed across versions), so the pointer is read fresh, never cached.
    public var lastSocketPathFileName: String {
        switch self {
        case .stable: return "last-socket-path"
        case .nightly: return "nightly-last-socket-path"
        }
    }

    var appBundleName: String {
        switch self {
        case .stable: return "cmux.app"
        case .nightly: return "cmux NIGHTLY.app"
        }
    }

    var temporarySocketPointerFileName: String {
        switch self {
        case .stable: return "cmux-last-socket-path"
        case .nightly: return "cmux-nightly-last-socket-path"
        }
    }
}

public enum CmuxSocketPin: Equatable {
    case pinned(String)
    case discover
    case noLiveSocket
}

/// Answers what to do with the selected channel's socket in one place: pin it, discover it,
/// or do not ask for it. `.discover` is safe for a single-channel user because when no other
/// channel is live, the only server discovery can reach is the selected channel's own.
public func cmuxSocketPin(
    channel: CmuxChannel, resolvedSocketPath: (CmuxChannel) -> String?
) -> CmuxSocketPin {
    if let socketPath = resolvedSocketPath(channel) {
        return .pinned(socketPath)
    }
    return CmuxChannel.allCases.contains {
        $0 != channel && resolvedSocketPath($0) != nil
    } ? .noLiveSocket : .discover
}

/// The explicit locations are first because the app's PATH is normally only `/usr/bin:/bin`.
/// The cmux bundle's resource executable is the canonical installation; the stable channel then
/// falls back to the two conventional standalone locations and the user's PATH, while nightly
/// searches only its bundle installations — a bare `cmux` on PATH cannot testify to its channel.
public func cmuxCLICandidatePaths(
    channel: CmuxChannel = .stable,
    homeDirectory: String = NSHomeDirectory(), path: String? = ProcessInfo.processInfo.environment["PATH"]
) -> [String] {
    let bundleCLI = "Contents/Resources/bin/cmux"
    var candidates = [
        "/Applications/\(channel.appBundleName)/\(bundleCLI)",
        (homeDirectory as NSString).appendingPathComponent(
            "Applications/\(channel.appBundleName)/\(bundleCLI)"
        ),
    ]
    guard channel == .stable else { return candidates }
    candidates += ["/opt/homebrew/bin/cmux", "/usr/local/bin/cmux"]

    if let path {
        candidates += path.split(separator: ":", omittingEmptySubsequences: true).map {
            (String($0) as NSString).appendingPathComponent("cmux")
        }
    }
    return candidates
}

public func findCmuxCLI(
    channel: CmuxChannel = .stable,
    homeDirectory: String = NSHomeDirectory(), path: String? = ProcessInfo.processInfo.environment["PATH"],
    isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
) -> String? {
    cmuxCLICandidatePaths(channel: channel, homeDirectory: homeDirectory, path: path)
        .first(where: isExecutable)
}

/// The channel's state-directory socket pointer path. The target is resolved from the pointer
/// rather than a fixed socket name because the socket basename changes across restarts and versions.
public func cmuxLastSocketPointerPath(
    channel: CmuxChannel, homeDirectory: String = NSHomeDirectory()
) -> String {
    (homeDirectory as NSString)
        .appendingPathComponent(".local/state/cmux/\(channel.lastSocketPathFileName)")
}

/// The state path is first because `/tmp` is periodically cleaned, so its copy stays accurate
/// longer; `/tmp` is second because it is the only remaining clue when the state path is absent.
public func cmuxSocketPointerPaths(
    channel: CmuxChannel, homeDirectory: String = NSHomeDirectory()
) -> [String] {
    [
        cmuxLastSocketPointerPath(channel: channel, homeDirectory: homeDirectory),
        "/tmp/\(channel.temporarySocketPointerFileName)",
    ]
}

/// A pointer whose target is gone means the channel's server left nothing behind — treat it the
/// same as no pointer at all rather than pinning a dead path.
public func cmuxResolvedSocketPath(
    pointerContents: String?, fileExists: (String) -> Bool
) -> String? {
    guard let contents = pointerContents else { return nil }
    let target = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !target.isEmpty, fileExists(target) else { return nil }
    return target
}

/// Resolves pointer contents in caller-provided order and returns the first live target.
public func cmuxFirstLiveSocketPath(
    pointerContents: [String?], fileExists: (String) -> Bool
) -> String? {
    for contents in pointerContents {
        if let path = cmuxResolvedSocketPath(pointerContents: contents, fileExists: fileExists) {
            return path
        }
    }
    return nil
}

/// Reads the channel's pointer file and answers the socket path to pin, or nil when the channel
/// has no live socket file to point at. The caller decides whether nil permits discovery or is a
/// missing channel identity that must launch or fail visibly.
public func cmuxChannelSocketPath(
    channel: CmuxChannel, homeDirectory: String = NSHomeDirectory(),
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> String? {
    let pointerContents = cmuxSocketPointerPaths(
        channel: channel, homeDirectory: homeDirectory
    ).map {
        try? String(contentsOfFile: $0, encoding: .utf8)
    }
    return cmuxFirstLiveSocketPath(
        pointerContents: pointerContents,
        fileExists: fileExists
    )
}

/// nil socket keeps the inherited environment untouched (CLI discovery); a socket merges on top
/// of the base so the child still has PATH and HOME. Socket paths here are file-system paths, so
/// Foundation's NFD re-encoding of `Process.environment` is absorbed by APFS name resolution.
public func cmuxRPCEnvironment(
    socketPath: String?, base: [String: String] = ProcessInfo.processInfo.environment
) -> [String: String]? {
    guard let socketPath else { return nil }
    var env = base
    env["CMUX_SOCKET_PATH"] = socketPath
    return env
}

/// Measured on Darwin 25.4.0 (pty probe with the master drained like a terminal emulator does):
/// a canonical-mode tty keeps exactly 1024 bytes of an unread line and silently discards the
/// rest — the CR included, and the writer sees every byte accepted. 1023 bytes + CR survive
/// whole. A command longer than this sent before the shell reads is truncated with no error
/// anywhere, and without its CR it sits unsubmitted in the prompt.
public let darwinCanonicalLineLimit = 1024

public enum CmuxCommandGate: Equatable {
    case send
    case waitLonger
    case sendDespiteCanonical
    case refuseTooLong
}

/// Whether the command may be typed into the pane yet. Raw mode means a line editor is reading —
/// no canonical buffer, so any length is safe. Without that observation, a payload within the
/// measured canonical limit is safe to send immediately because the buffer preserves all of it,
/// including CR. Only a larger payload waits for raw mode; if raw mode is still unknown at the
/// deadline, that payload is refused rather than silently truncated.
public func cmuxCommandSendGate(
    rawModeObserved: Bool?, deadlineExpired: Bool, payloadByteCount: Int
) -> CmuxCommandGate {
    if rawModeObserved == true { return .send }
    if payloadByteCount <= darwinCanonicalLineLimit { return .sendDespiteCanonical }
    return deadlineExpired ? .refuseTooLong : .waitLonger
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
/// change a running instance's socket mode. An unkeyed workspace.create is not idempotent, so
/// timeouts, malformed responses, and post-create failures are rethrown because the server may
/// already have created a workspace. Grouped creates carry one stable operation_id and may reuse
/// the exact same keyed request after a measured reachability failure: a live repeat is at-most-once,
/// while the typed already_completed result is terminal and never authorizes regeneration. What
/// counts as transport proof is classifyCmuxCLIFailure below, which fails closed on anything it
/// has not measured.
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

/// The grouped create shape builds on the legacy focus-only parameters so the single-request
/// path keeps its exact wire contract.
public func cmuxWorkspaceCreateParameters(
    for plan: CmuxWorkspaceCreatePlan, commands: [String]
) -> [String: Any] {
    var parameters = cmuxWorkspaceCreateParameters()
    parameters["layout"] = cmuxLayoutJSON(for: plan.layout.tree, commands: commands)
    parameters["operation_id"] = plan.operationID
    if let title = plan.title { parameters["title"] = title }
    return parameters
}

public func cmuxWorkspaceListParameters() -> [String: Any] {
    [:]
}

public func cmuxPaneListParameters(workspaceID: String) -> [String: Any] {
    ["workspace_id": workspaceID]
}

public func cmuxSurfaceListParameters(workspaceID: String) -> [String: Any] {
    ["workspace_id": workspaceID]
}

public func cmuxSurfaceSplitParameters(
    surfaceID: String, direction: CmuxSurfaceSplitDirection
) -> [String: Any] {
    ["surface_id": surfaceID, "direction": direction.rawValue]
}

public func cmuxSurfaceCreateParameters(
    workspaceID: String, paneID: String
) -> [String: Any] {
    ["workspace_id": workspaceID, "pane_id": paneID]
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
    cli: String, method: String, params: [String: Any] = [:], timeout: TimeInterval = 10,
    socketPath: String? = nil
) throws -> [String: Any] {
    let arguments: [String]
    do {
        arguments = try cmuxRPCArguments(method: method, params: params)
    } catch let error as CmuxRPCError {
        throw TerminalError.cmuxRPCFailed("\(method): \(error.description)")
    }

    let result: (status: Int32, stdout: String, stderr: String)
    do {
        result = try runProcess(
            cli, arguments, env: cmuxRPCEnvironment(socketPath: socketPath), timeout: timeout
        )
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
