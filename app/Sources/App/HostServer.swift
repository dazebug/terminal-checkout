import Core
import Foundation

/// The names the protocol uses for the locale generation. Snake case, like `command_template` and
/// `claude_inputs` — the extension reads these, so they are the wire format rather than a detail.
let localeQueryName = "locale"
let localeResponseKey = "locale"
let localeInstallIdResponseKey = "locale_install_id"
let localeEpochResponseKey = "locale_epoch"

/// What the extension asked for.
///
/// The query exists because the extension has to know the language **before** it draws anything, and
/// the only other way to find out would be to send a command — which opens a terminal tab nobody
/// asked for. It is answered here and not in `Request.swift`: a query is a concern of the app's
/// protocol envelope, and Core's command resolver must not learn about app state (D23). Core
/// ignoring unknown top-level keys is also what lets an **older** app answer this request at all —
/// it sees a request with no `command_template`, says so, and that answer carries no locale
/// metadata, which is exactly how the extension is told "no input" rather than "change nothing".
enum HostRequestKind: Equatable {
    case localeQuery
    case command
}

/// One field decides. Anything that does not name a query is a command request, including the empty
/// and the malformed ones — they keep going to Core and keep getting Core's verdict, unchanged.
func hostRequestKind(_ json: [String: Any]) -> HostRequestKind {
    (json["query"] as? String) == localeQueryName ? .localeQuery : .command
}

/// Attaches the published locale to a response — **to every response this app composes**.
///
/// That is a correction. The rule used to be "only one that succeeded", and the reasoning behind it
/// was that a rule with no exceptions is the one the extension can implement without a table. The
/// rule was exceptionless; it was also wrong about which question it was answering.
///
/// **A validation failure can be the first successful contact with the running app.** The
/// extension's cold-start query may never have run, may have failed, or may have been answered by an
/// older app — and then the user presses a button, the relay launches this app, and this app refuses
/// the command. The app is up and has a language; under the old rule the one response that could
/// have said so said nothing, and the extension stayed in the wrong language for as long as the
/// user kept making mistakes. The cold-start query does not cover that: it already happened.
///
/// Carrying it costs nothing, which is the other half. The publication is in hand before
/// `handleRequest` is even called, so a refusal has the same thing to say as a success does.
///
/// The boundary is now **origin, not outcome**, and it is the rule with fewer exceptions of the two:
/// everything this app composes about itself — a successful command, a refused one, an answered
/// query — carries the generation, and everything it did not compose carries nothing and is no input
/// to the extension's cache. The things it did not compose are not a list to remember: a relay
/// error, a transport failure and an older app's answer never pass through this function at all.
///
/// The one response that comes close to the line is the internal-error literal in `serve` — this app
/// emits it, but it emits it *instead of* a statement about itself, at the moment it could not turn
/// its own response into JSON. It does not come through here, and it should not: attaching the
/// generation would mean hand-assembling JSON exactly where JSON assembly has just failed, with an
/// install id that would then need escaping. A response the app could not compose is not a response
/// the app made a claim in.
///
/// A `nil` publication means nothing has been published on this machine yet — the headless server
/// never invents one (D49) — and it produces the same metadata-free response for the same reason.
func responseCarryingLocale(
    _ response: [String: Any], publication: LocalePublication?
) -> [String: Any] {
    guard let publication else { return response }
    var carried = response
    carried[localeResponseKey] = publication.snapshot.tag
    carried[localeInstallIdResponseKey] = publication.installId
    carried[localeEpochResponseKey] = publication.snapshot.epoch
    return carried
}

/// The whole decision for one decoded request: which kind it is, what it answers, and what rides
/// along.
///
/// A function of its arguments, so that all four responses can be enumerated in a test — the
/// alternative is a socket, a terminal, and a machine whose stored publication decides the outcome.
/// `run` is never called for a query, which is the half of this contract that keeps a cold start
/// from opening a tab.
func hostResponse(
    json: [String: Any], publication: LocalePublication?, baseDirectory: String,
    run: (ResolvedRequest) throws -> Void
) -> [String: Any] {
    switch hostRequestKind(json) {
    case .localeQuery:
        return responseCarryingLocale(["success": true], publication: publication)
    case .command:
        return responseCarryingLocale(
            handleRequest(json: json, baseDirectory: baseDirectory, run: run),
            publication: publication
        )
    }
}

/// **What this process will say about the language, settled before it answers anything.**
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
    /// what D49 rules out. It answers with whatever the GUI last published and adds nothing of its
    /// own.
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
        /// between. Answering on that socket would mean answering out of the previous launch's
        /// snapshot, so the bind is given back instead of being served.
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
    /// Where the published locale is committed at launch and read again for every answer. A
    /// parameter for the same reason `LocaleState.publish` and `Settings.setLanguage` take one: the
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
    /// answered, with the committed publication, when the loop starts.
    ///
    /// It is `@discardableResult` because the announcement is now what a caller says, and the value
    /// is a fact about the bind that only the tests and the process-wide `current` still read.
    ///
    /// `publish` is the launch publisher, as a parameter with the production default — the same
    /// arrangement `warpInjectionSetup` uses, and for the same reason: the branch where a
    /// publication does not happen is otherwise unreachable from outside. With the seam closed
    /// (`LocalePublicationRight.whileHeld`) a right cannot be lost *during* the write, so the only
    /// remaining way to be refused is a right already given up when this line is reached, which
    /// takes another thread relinquishing between two statements here. **It cannot weaken what this
    /// call establishes**: whatever is passed runs before the accept loop is armed and its refusal
    /// is still handled here, so the ordering and the guard are both outside it. The default being
    /// the real publisher is not taken on faith either —
    /// `testNoRequestIsAnsweredBeforeTheLaunchPublicationIsCommitted` drives this call with no
    /// argument and observes the real write.
    @discardableResult
    func start(
        announcing announcement: LocaleAnnouncement,
        publish: (SupportedLocale, LocalePublicationRight, UserDefaults) -> LocalePublication?
            = { Settings.publishLocaleAtLaunch(resolved: $0, right: $1, defaults: $2) }
    ) throws -> LocalePublicationRight {
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
            // then the answer to give is the one a failed bind already gets: this instance owns
            // nothing and says nothing, and it does not answer either
            guard publish(resolved, right, defaults) != nil else {
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
            // What this process may say about the language: whatever the GUI last published. The
            // role is `.headless` **in both processes**, and that is the point — the server is a
            // reader. A server publishing as `.interactive` would be a second writer racing the
            // picker for the same epoch, which is the P0 round 10 named; the one writer is the GUI,
            // at launch and at the picker (`Settings.publishLocaleAtLaunch`, `Settings.language`).
            let publication = LocaleState.publish(
                resolved: AppLocalization.resolvedLocale(defaults: defaults),
                defaults: defaults, role: .headless
            )
            let response = execQueue.sync {
                // Like the terminal choice, the base directory has the app's settings as its
                // single source — hand over the stored string only; validation, normalization,
                // and `{cd}` assembly belong to Core (no logic here)
                hostResponse(
                    json: json, publication: publication, baseDirectory: Settings.baseDirectory
                ) { resolved in
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
