import Core
import Foundation

/// **What this process will publish about the language, settled before it answers anything.**
///
/// It is a required argument of `start(announcing:)`, and that is the whole of the mechanism: there
/// is no bind without an announcement, no API surface between committing it and arming the accept
/// loop, and therefore no order for a caller to get wrong. What used to stand there was two
/// statements in `AppDelegate` — bind, then publish — with the accept loop already running between
/// them, so the first thing the extension asked was answered out of whatever this machine published
/// the last time it ran (round 17 review). The relay is *waiting on that listen*, so the window was
/// not a rare interleaving; it was the ordinary startup path.
///
/// Both binaries reach it and neither can skip it, which is the other half of the constraint. The
/// headless server publishes nothing, and `.nothing` is how it says so **at the call site** — it
/// used to say it by discarding a return value, which is a sentence only to a reader who knows what
/// was discarded.
enum LocaleAnnouncement {
    /// The GUI that owns the socket: publish this launch's locale under the right the bind produced.
    /// `auto` is a promise about the *system's* language and the system's language can change while
    /// the app is not running, which is why a launch publishes at all (D48).
    case publish(SupportedLocale)
    /// `--headless-server`: it draws nothing and has no picker, so inventing a revision there is
    /// what D49 rules out. Its command responses come from Core and carry no locale publication.
    case nothing
}

/// The unix socket server that takes the relay's requests and runs them in the terminal.
final class HostServer {
    /// A diagnostic surface and not a message to the user: the only reader is `AppDelegate`, which
    /// writes it to the log. English for the same reason Core's strings are (D27).
    enum ServerError: Error, CustomStringConvertible {
        case alreadyRunning
        case socketFailed(String)
        /// The bind succeeded and the launch publication did not — the right was given up in
        /// between. Serving a socket whose launch publication failed would leave the process's
        /// ownership/publication invariant broken, so the bind is given back instead.
        case publicationRefused

        var description: String {
            switch self {
            case .alreadyRunning: return "another Terminal Checkout instance is already running"
            case .socketFailed(let reason): return "creating the socket failed: \(reason)"
            case .publicationRefused:
                return "the socket was bound but the launch locale could not be published"
            }
        }
    }

    private let socketPath: String
    /// Everything this instance owns, or nothing. Three separate properties is what let a teardown
    /// see half of a startup (round 20 review).
    private var bound: BoundSocket?
    /// **Starting and stopping are one transition each, and they do not interleave.** The window was
    /// not between two lines that could be swapped: it ran from the moment the socket existed to the
    /// moment the server was answering, and a `stop()` could land anywhere in it. So both take this,
    /// and `start`'s own failure paths call the half that assumes it is already held — `NSLock` is
    /// not recursive, and calling `stop()` there would deadlock.
    ///
    /// Lock order, which is why there is no inversion to have: this one is taken **first** and
    /// `LocalePublicationRight`'s is always last (`start` → `commit` → `whileHeld`; `tearDown` →
    /// `relinquish`). Nothing takes them the other way round.
    private let lifecycle = NSLock()
    /// Where the published locale is committed at launch. A parameter for the same reason
    /// `LocaleState.publish` and `Settings.setLanguage` take one: the
    /// subject is a `UserDefaults` write, and a case that drove it against `.standard` would be
    /// rewriting the language state of whatever app owns this process's domain.
    private let defaults: UserDefaults
    private let acceptQueue = DispatchQueue(label: "terminal-checkout.accept")
    private let execQueue = DispatchQueue(label: "terminal-checkout.exec") // serializes terminal launches

    init(socketPath: String, defaults: UserDefaults = .standard) {
        self.socketPath = socketPath
        self.defaults = defaults
    }

    /// The right to publish a locale comes back from here, and from nowhere else, because binding
    /// this path is what makes a process **the** Terminal Checkout on this machine — the one the
    /// relay reaches and the extension is therefore talking to.
    ///
    /// **Binding, announcing and answering are one call, in that order.** Splitting them is what the
    /// round 17 review found: the accept loop was armed on the way out and the caller published
    /// afterwards, so between `listen()` and that line the server was answering with the previous
    /// launch's snapshot — and for an `auto` user whose system language changed while the app was
    /// down, that is the feature failing in the one scenario it exists for. The value returned below
    /// arms nothing and there is no second method to call, so the two orders are not two orders: the
    /// announcement is committed by the statement above the one that arms accepting, with nothing
    /// between them that a caller can reach.
    ///
    /// `listen()` stays where it was, next to `bind`, rather than moving below the announcement.
    /// What has to be true is that nothing is *answered* before the announcement is committed, and
    /// that is what arming decides; moving `listen` down would instead widen the window in which
    /// this socket looks dead to another instance's stale-path probe, which is a live race of its
    /// own. A connection that arrives during the announcement waits in the kernel's backlog and is
    /// answered with Core's command output when the loop starts.
    ///
    /// It is `@discardableResult` because the announcement is now what a caller says, and the value
    /// is a fact about the bind that only the tests and the process-wide `current` still read.
    ///
    /// **There is no injectable publisher any more** (round 24 review). One was added so a case could
    /// reach the branch where publication does not happen, and it was a test seam that compiled in
    /// production: `start(announcing: .publish(.ja), publish: { … .ko … })` announced one locale and
    /// wrote another. Two things removed the need for it — the store is injectable, so a case can
    /// hold the write open through that; and a right now names the path it bound, so a server on a
    /// path that is not the relay's is refused **the way production would refuse it**, which is a
    /// better fixture than a closure that returns nil.
    @discardableResult
    func start(announcing announcement: LocaleAnnouncement) throws -> LocalePublicationRight {
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

        // The bind and the right come back together, from the type whose invariant they are
        var bound = try LocalePublicationRight.bindingSocket(at: socketPath)
        chmod(socketPath, 0o600)
        bound.identity = Self.identity(ofPathAt: socketPath)
        self.bound = bound
        let fd = bound.fd
        let right = bound.right
        switch announcement {
        case .publish(let resolved):
            // **What was attempted is not what was claimed.** `publishLocaleAtLaunch` used to answer
            // nothing and this line used to ignore it, so the accept loop was armed whether or not a
            // publication had happened — the invariant held was "a publication was attempted" while
            // the one written down was "the publication is committed before anything is answered"
            // (round 18 review). The right can be given up between the mint above and the write, and
            // then this instance owns nothing and says nothing, so it does not answer either
            guard Settings.publishLocaleAtLaunch(
                resolved: resolved, right: right, defaults: defaults
            ) != nil else {
                tearDown()
                throw ServerError.publicationRefused
            }
        case .nothing:
            break
        }
        // The door opens last. Everything above has already happened by the time the first request
        // can be answered, and this is the only line in the program that starts answering
        acceptQueue.async { [weak self] in self?.acceptLoop(serverFD: fd) }
        return right
    }

    /// **Only what this instance owns is taken down.**
    ///
    /// The publication right goes first: from here on this process must not move a generation the
    /// extension orders by, because it is no longer the process the relay can reach.
    ///
    /// Then the path — but only while it still names the file the bind created. It used to be
    /// unlinked unconditionally, which is a deletion by name: an instance that closed its listener
    /// while another was binding the same path would remove **the new owner's** socket, leaving a
    /// process that believes it owns the machine and a relay that cannot connect to it (round 16
    /// review). Nothing is deleted when this server never bound, for the same reason.
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

    /// The same thing **with the lifecycle lock already held** — the only reason it exists
    /// separately, and the same reason `LocalePublicationRight.giveUp` does: `NSLock` is not
    /// recursive, so `start`'s own failure paths cannot call `stop()`.
    private func tearDown() {
        guard let bound else { return }
        bound.right.relinquish()
        if let identity = bound.identity, let now = Self.identity(ofPathAt: socketPath), now == identity {
            unlink(socketPath)
        }
        close(bound.fd)
        self.bound = nil
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
                handleRequest(json: json, baseDirectory: Settings.baseDirectory) { resolved in
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
                    // interval — the window a restart used to be admitted through (round 14, P0).
                    // Refused means the app is already leaving, and the request fails rather than
                    // opening a tab whose input would be dropped. The slot is then handed to the
                    // launch, which writes the helper's address into it before creating anything —
                    // this side no longer records after the fact, because there is no moment at
                    // which it could that the launch has not already passed (round 16, P0)
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
                }
            }
            let payload = (try? JSONSerialization.data(withJSONObject: response))
                ?? Data(#"{"success":false,"error":"internal error"}"#.utf8)
            if !writeFramedMessage(payload, toFD: fd) { break }
        }
    }
}
