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

/// The values HostServer hands to the grouped executor. Keeping the deadline closure with the
/// prepared batch lets the production factory use the same request budget as the test seam.
struct CmuxBatchExecutionRequest {
    let prepared: [PreparedRequest]
    let plan: CmuxPlacementPlan
    let channel: CmuxChannel
    let deadlineExceeded: () -> Bool
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
    private let runInTerminalFactory: (
        String, Terminal, ClaudeDelivery.Admission?
    ) throws -> TerminalSessionHandle
    private let runCmuxBatchFactory: (CmuxBatchExecutionRequest) -> CmuxGroupedExecution
    private let timelineFactory: (Date, String?) -> DeliveryTimeline
    private let log: (String) -> Void
    private let now: () -> Date
    private let monotonicNow: () -> TimeInterval
    /// Test-only pause before serial admission; production leaves it nil.
    private let beforeExecQueueAdmission: (() -> Void)?

    /// A test-only pause lets the ownership suite hold startup between binding and arming the
    /// accept loop. Production leaves it nil; the lifecycle lock remains the real guarantee.
    var beforeAccepting: (() -> Void)?

    init(
        socketPath: String,
        runInTerminal: @escaping (
            _ command: String, _ terminal: Terminal, _ claudeInput: ClaudeDelivery.Admission?
        ) throws -> TerminalSessionHandle = Core.runInTerminal,
        runCmuxBatch: @escaping (CmuxBatchExecutionRequest) -> CmuxGroupedExecution = { request in
            Core.runCmuxBatch(
                commands: request.prepared.map(\.command),
                plan: request.plan,
                channel: request.channel,
                deadlineExceeded: request.deadlineExceeded
            )
        },
        timelineFactory: @escaping (Date, String?) -> DeliveryTimeline = { arrival, label in
            DeliveryTimeline(startedAt: arrival, label: label)
        },
        log: @escaping (String) -> Void = checkoutLog,
        now: @escaping () -> Date = Date.init,
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        beforeExecQueueAdmission: (() -> Void)? = nil
    ) {
        self.socketPath = socketPath
        self.runInTerminalFactory = runInTerminal
        self.runCmuxBatchFactory = runCmuxBatch
        self.timelineFactory = timelineFactory
        self.log = log
        self.now = now
        self.monotonicNow = monotonicNow
        self.beforeExecQueueAdmission = beforeExecQueueAdmission
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
            // A stopwatch over each item's success path. It starts **when the request arrived**, before
            // the serial launch queue, so every item's "total" stays on the same axis as the wait the
            // user feels after pressing the button.
            let requestArrival = now()
            // Date remains the display anchor; uptime keeps clock adjustments from reopening the response budget.
            let requestArrivalMonotonic = monotonicNow()
            var hasLoggedBatchWarpWarning = false
            beforeExecQueueAdmission?()
            let response = execQueue.sync {
                // The terminal choice has the app's settings as its single source — the request's `terminal` field is ignored.
                let terminal = Settings.terminal
                // Like the terminal choice, the base directory has the app's settings as its
                // single source — hand over the stored string only; validation, normalization,
                // and `{cd}` assembly belong to Core (no logic here)
                let runBatch: BatchRun?
                if let channel = terminal.cmuxChannel, json["items"] != nil {
                    runBatch = { resolvedItems in
                        self.runCmuxBatch(
                            resolvedItems,
                            channel: channel,
                            requestArrival: requestArrival,
                            requestArrivalMonotonic: requestArrivalMonotonic
                        )
                    }
                } else {
                    runBatch = nil
                }
                return handleRequest(json: json, baseDirectory: Settings.baseDirectory, run: {
                    resolved, position in
                    let timelineLabel = position.map { "item \($0.index)/\($0.total)" }
                    let timeline = self.timelineFactory(requestArrival, timelineLabel)
                    if let position,
                       position.index > 1,
                       monotonicNow() - requestArrivalMonotonic >= batchLaunchResponseBudget {
                        timeline.step(batchResponseDeadlineExceededMessage)
                        throw CommandError.badRequest(batchResponseDeadlineExceededMessage)
                    }
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
                    if let position,
                       terminal == .warp,
                       !prepared.claudeInputs.isEmpty,
                       !hasLoggedBatchWarpWarning {
                        hasLoggedBatchWarpWarning = true
                        log(
                            "a Warp batch of \(position.total) item(s) schedules typed claude input"
                                + " (first at item \(position.index)) — delivery needs the Accessibility permission"
                                + " and each tab watched"
                        )
                    }
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
                    let handle = try self.runInTerminalFactory(prepared.command, terminal, admission)
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
                    },
                    notLaunched: { position, reason in
                        // A content-rejected batch never reaches `run`, so the per-item timeline
                        // contract is honored here: one labeled timeline whose only stage is the
                        // same reason the item's response carries.
                        let timeline = self.timelineFactory(
                            requestArrival, "item \(position.index)/\(position.total)"
                        )
                        timeline.step(reason)
                    },
                    runBatch: runBatch,
                    message: localizedErrorMessage
                )
            }
            let payload = (try? JSONSerialization.data(withJSONObject: response))
                ?? Data(#"{"success":false,"error":"internal error"}"#.utf8)
            if !writeFramedMessage(payload, toFD: fd) { break }
        }
    }

    private func runCmuxBatch(
        _ resolvedItems: [ResolvedRequest],
        channel: CmuxChannel,
        requestArrival: Date,
        requestArrivalMonotonic: TimeInterval
    ) -> [Result<Void, Error>] {
        let timelines = resolvedItems.indices.map { index in
            timelineFactory(requestArrival, "item \(index + 1)/\(resolvedItems.count)")
        }
        let preparedItems = resolvedItems.map {
            prepareRequest($0, claudeIsExecutable: Settings.claudeIsExecutable)
        }

        for index in resolvedItems.indices {
            let prepared = preparedItems[index]
            let resolved = resolvedItems[index]
            let route = prepared.claudeInputs.isEmpty
                ? (resolved.claudeInputs.isEmpty ? "no claude input" : "merged into argv")
                : "typing \(prepared.claudeInputs.count)"
            timelines[index].step(
                "request received — \(resolved.claudeInputs.count) claude input(s), \(route)"
            )
        }

        let preset = CmuxPlacementPreset.parse(
            rawIdentityMode: Settings.cmuxPlacementIdentityMode,
            rawFixedName: Settings.cmuxPlacementFixedName,
            rawArrangement: Settings.cmuxPlacementArrangement
        )
        let plan = cmuxPlacementPlan(
            preset: preset,
            commandByteCounts: preparedItems.map { $0.command.utf8.count },
            batchOperationID: UUID(),
            itemOperationIDs: resolvedItems.map { _ in UUID() }
        )

        var admissions = Array<ClaudeDelivery.Admission?>(
            repeating: nil, count: preparedItems.count
        )
        for index in preparedItems.indices where !preparedItems[index].claudeInputs.isEmpty {
            guard let admission = ClaudeDelivery.admit() else {
                let error = TerminalError.goingAway
                for admission in admissions { admission?.end() }
                for timeline in timelines { timeline.step(localizedErrorMessage(error)) }
                return Array(repeating: .failure(error), count: resolvedItems.count)
            }
            admissions[index] = admission
        }

        let monotonicClock = monotonicNow
        let execution = runCmuxBatchFactory(CmuxBatchExecutionRequest(
            prepared: preparedItems,
            plan: plan,
            channel: channel,
            deadlineExceeded: {
                monotonicClock() - requestArrivalMonotonic >= batchLaunchResponseBudget
            }
        ))
        var placementMessage = "cmux grouped placement: \(String(describing: execution.path))"
        if execution.didFallbackToTabs {
            placementMessage += " (pane fallback to tabs, N=\(resolvedItems.count))"
        }
        for timeline in timelines { timeline.step(placementMessage) }
        log(placementMessage)

        guard execution.results.count == preparedItems.count else {
            let reason = "grouped batch execution returned \(execution.results.count) result(s) for \(resolvedItems.count) item(s)"
            for timeline in timelines { timeline.step(reason) }
            for admission in admissions { admission?.end() }
            return execution.results.map { result in
                switch result {
                case .success:
                    return .success(())
                case .failure(let error):
                    return .failure(error)
                }
            }
        }

        var results: [Result<Void, Error>] = []
        results.reserveCapacity(execution.results.count)
        for index in execution.results.indices {
            switch execution.results[index] {
            case .success(let handle):
                timelines[index].step("cmux tab created")
                if let admission = admissions[index] {
                    let inputs = preparedItems[index].claudeInputs
                    let timeline = timelines[index]
                    DispatchQueue.global(qos: .utility).async {
                        deliverClaudeInputs(
                            inputs, to: handle, timeline: timeline, admission: admission
                        )
                    }
                }
                results.append(.success(()))
            case .failure(let error):
                timelines[index].step(localizedErrorMessage(error))
                admissions[index]?.end()
                results.append(.failure(error))
            }
        }
        return results
    }
}
