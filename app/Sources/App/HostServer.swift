import Core
import Foundation

/// The descriptor and pathname identity produced by a successful socket bind.
///
/// The value stays together through startup and teardown: a stop arriving during startup cannot
/// close a descriptor before the instance has recorded which pathname it created.
private struct BoundSocket {
    let fd: Int32
    var identity: (dev: dev_t, ino: ino_t)?
}

/// The unix socket server that takes the relay's requests and runs them in the terminal.
final class HostServer {
    /// A diagnostic surface and not a message to the user: the only reader is `AppDelegate`, which
    /// writes it to the log. English for the same reason Core's strings are.
    enum ServerError: Error, CustomStringConvertible {
        case alreadyRunning
        case socketFailed(String)
        var description: String {
            switch self {
            case .alreadyRunning: return "another Terminal Checkout instance is already running"
            case .socketFailed(let reason): return "creating the socket failed: \(reason)"
            }
        }
    }

    private let socketPath: String
    /// Everything this instance owns, or nothing. Three separate properties is what let a teardown
    /// see half of a startup.
    private var bound: BoundSocket?
    /// **Starting and stopping are one transition each, and they do not interleave.** Both take this
    /// lock; `stop()` calls the lock-held teardown half rather than recursively acquiring `NSLock`.
    /// Startup and teardown therefore cannot observe half of the other transition.
    private let lifecycle = NSLock()
    private let acceptQueue = DispatchQueue(label: "terminal-checkout.accept")
    private let execQueue = DispatchQueue(label: "terminal-checkout.exec") // serializes terminal launches

    /// A test-only pause lets the ownership suite hold startup between binding and arming the
    /// accept loop. Production leaves it nil; the lifecycle lock remains the real guarantee.
    var beforeAccepting: (() -> Void)?

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    /// Binds the socket, records the file identity, and then arms the accept loop. Every request is
    /// a command; no locale state is read or written on this path.
    func start() throws {
        lifecycle.lock()
        defer { lifecycle.unlock() }

        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // An existing socket: if it accepts a connection there is a live instance, otherwise it is
        // stale — remove it and take the path over
        if FileManager.default.fileExists(atPath: socketPath) {
            if let fd = connectToUnixSocket(path: socketPath) {
                close(fd)
                throw ServerError.alreadyRunning
            }
            unlink(socketPath)
        }

        var bound = try Self.bindingSocket(at: socketPath)
        chmod(socketPath, 0o600)
        bound.identity = Self.identity(ofPathAt: socketPath)
        self.bound = bound
        let fd = bound.fd
        beforeAccepting?()
        acceptQueue.async { [weak self] in self?.acceptLoop(serverFD: fd) }
    }

    /// **Only what this instance owns is taken down.** The path is removed only while it still names
    /// the file this bind created; deleting by name could remove a replacement listener. Nothing is
    /// deleted when this server never bound.
    ///
    /// Between the comparison and the `unlink` the file can still be replaced — macOS has no
    /// `funlinkat`, so the last step is by path. That is the same residual the Warp helper's preamble
    /// records for socket and Tab Config reclaim, narrowed the same way and not closed.
    /// It takes the lifecycle lock and `tearDown` does the work, so that a teardown arriving during
    /// a startup **waits for it** instead of taking half of it apart.
    func stop() {
        lifecycle.lock()
        defer { lifecycle.unlock() }
        tearDown()
    }

    /// The lock-held half of `stop()`. It is separate so the public transition does not recursively
    /// acquire `NSLock`.
    private func tearDown() {
        guard let bound else { return }
        if let identity = bound.identity, let now = Self.identity(ofPathAt: socketPath), now == identity {
            unlink(socketPath)
        }
        close(bound.fd)
        self.bound = nil
    }

    private static func bindingSocket(at path: String) throws -> BoundSocket {
        guard var address = makeUnixSockaddr(path) else {
            throw ServerError.socketFailed("the path is too long: \(path)")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ServerError.socketFailed(String(cString: strerror(errno)))
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw ServerError.socketFailed(reason)
        }
        return BoundSocket(fd: fd)
    }

    /// Which file the name points at right now, or nil if it points at nothing.
    private static func identity(ofPathAt path: String) -> (dev: dev_t, ino: ino_t)? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (info.st_dev, info.st_ino)
    }

    private func acceptLoop(serverFD: Int32) {
        while true {
            let fd = accept(serverFD, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                break // the server socket was closed
            }
            // Only processes belonging to the same user
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                close(fd)
                continue
            }
            DispatchQueue.global().async { [weak self] in self?.serve(fd: fd) }
        }
    }

    private func serve(fd: Int32) {
        defer { close(fd) }
        while let data = readFramedMessage(fromFD: fd) {
            // Whatever the request goes on to do, its arrival is the evidence that the
            // Chrome → relay → socket path works
            Settings.recordRequestEvidence()
            let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
            // A stopwatch over the steps of the success path. It starts **when the request
            // arrived**, so every "total" below it is on the same axis as the wait the user feels
            // after pressing the button
            let timeline = DeliveryTimeline()
            let response = execQueue.sync {
                // Like the terminal choice, the base directory has the app's settings as its
                // single source — hand over the stored string only; validation, normalization,
                // and `{cd}` assembly belong to Core (no logic here)
                handleRequest(json: json, baseDirectory: Settings.baseDirectory, run: { resolved in
                    // Which route the scheduled claude input takes is `prepareRequest`'s verdict —
                    // exactly one plain-text input rides in argv, everything else is typed (a run of
                    // consecutive `!` merges into one line only when the safety gate allows it)
                    let prepared = prepareRequest(
                        resolved, claudeIsExecutable: Settings.claudeIsExecutable
                    )
                    let route = prepared.claudeInputs.isEmpty
                        ? (resolved.claudeInputs.isEmpty ? "no claude input" : "merged into argv")
                        : "typing \(prepared.claudeInputs.count)"
                    timeline.step("request received — \(resolved.claudeInputs.count) claude input(s), \(route)")
                    // The terminal choice has the app's settings as its single source — the
                    // request's `terminal` field is ignored
                    let terminal = Settings.terminal
                    // **The slot is reserved before anything can launch a helper**, not when the
                    // delivery starts: `runInTerminal` brings the Warp helper up, and the watch
                    // below runs asynchronously, so a registration taken there is late by that whole
                    // interval — a restart could otherwise be admitted through it.
                    // Refused means the app is already leaving, and the request fails rather than
                    // opening a tab whose input would be dropped. The slot is then handed to the
                    // launch, which writes the helper's address into it before creating anything —
                    // this side no longer records after the fact, because there is no moment at
                    // which it could know that the launch has not already passed.
                    var admission: ClaudeDelivery.Admission?
                    if !prepared.claudeInputs.isEmpty {
                        guard let token = ClaudeDelivery.admit() else { throw TerminalError.goingAway }
                        admission = token
                    }
                    // Every path out of here that is not a started delivery has to give the slot
                    // back, including the throwing ones
                    var deliveryStarted = false
                    defer { if let admission, !deliveryStarted { admission.end() } }
                    let handle = try runInTerminal(
                        command: prepared.command, terminal: terminal, claudeInput: admission
                    )
                    timeline.step("\(terminal.rawValue) tab created")
                    // The reservation **is** "this request has input to deliver" — the same value the
                    // launch was given, so the launch and the watch cannot disagree about it
                    if let admission {
                        // Watching the delivery can take minutes — waiting for claude to come up
                        // and the per-input retries both block — so the response goes back as soon
                        // as the tab is spawned and the watch runs outside the serial execQueue,
                        // which would otherwise hold up both that queue and Chrome's answer
                        deliveryStarted = true
                        DispatchQueue.global(qos: .utility).async {
                            deliverClaudeInputs(
                                prepared.claudeInputs, to: handle, timeline: timeline,
                                admission: admission
                            )
                        }
                    }
                    }, message: localizedErrorMessage
                )
            }
            let payload = (try? JSONSerialization.data(withJSONObject: response))
                ?? Data(#"{"success":false,"error":"internal error"}"#.utf8)
            if !writeFramedMessage(payload, toFD: fd) { break }
        }
    }
}
