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

/// **The right to publish a locale, as a thing you have rather than a question you ask.**
///
/// Round 14 bound the launch publisher to the socket and left the picker unbound; round 15 made both
/// ask one type, and the answer was a process-global boolean. A boolean is a *convention*: it says
/// what somebody recorded, not what anybody holds, and the launch writer went on publishing without
/// consulting it while a comment at the call site declared the rule for both (round 16 review). So
/// the answer is a value now. Its initialiser is file-private and the only line in this file that
/// makes one is the successful `bind`, so **no call site anywhere can publish without having been
/// handed one by the bind** — a third writer cannot be written wrong, only unwritable.
///
/// **Ownership lasts exactly as long as the socket does.** The path can be taken over: this process
/// stops listening, another binds the same path, and from then on the relay is talking to that one.
/// A right that outlived its socket would let this process go on moving a generation the extension
/// orders by while nothing can reach it. So `stop()` gives the right up, and a right that has been
/// given up writes nothing (`LocaleWriterRole.mayWrite`) — the same behaviour as the headless reader,
/// which is what a process that no longer owns the machine's socket is.
final class LocalePublicationRight {
    private static let lock = NSLock()
    private static var holder: LocalePublicationRight?

    /// What this process holds. Nil in an instance that lost the bind (`alreadyRunning`), in a
    /// process that never started a server, and after the socket has been given up. It is read
    /// rather than passed in the two places that cannot be handed a value — the picker and the
    /// window that draws it — and reading it is not a way around anything: **what it answers is
    /// whether we hold one, and holding one is the fact.**
    static var current: LocalePublicationRight? {
        lock.lock()
        defer { lock.unlock() }
        return holder
    }

    private var held = true

    private init() {}

    /// Minted by a successful bind. Any right this process was holding is given up first: two live
    /// rights would mean two answers to a question with one true answer.
    fileprivate static func mint() -> LocalePublicationRight {
        lock.lock()
        let previous = holder
        let right = LocalePublicationRight()
        holder = right
        lock.unlock()
        previous?.relinquish()
        return right
    }

    /// Still ours? False once the socket it came from has been let go.
    var isHeld: Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return held
    }

    /// Given up with the socket. Idempotent, and it clears the process-wide holder only if that is
    /// still this one — a right superseded by a later bind must not take the newer one down with it.
    fileprivate func relinquish() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        held = false
        if Self.holder === self { Self.holder = nil }
    }
}

/// The unix socket server that takes the relay's requests and runs them in the terminal.
final class HostServer {
    /// A diagnostic surface and not a message to the user: the only reader is `AppDelegate`, which
    /// writes it to the log. English for the same reason Core's strings are (D27).
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
    private var serverFD: Int32 = -1
    /// Which file at that path is **ours** — the device and inode the bind created. Remembered
    /// because the path is a name that can come to mean something else: another instance can take
    /// the path over while this one is stopping, and a teardown that goes by the name alone deletes
    /// the socket the relay is now talking to (round 16 review).
    private var boundIdentity: (dev: dev_t, ino: ino_t)?
    private var right: LocalePublicationRight?
    private let acceptQueue = DispatchQueue(label: "terminal-checkout.accept")
    private let execQueue = DispatchQueue(label: "terminal-checkout.exec") // serializes terminal launches

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    /// The right to publish a locale comes back from here, and from nowhere else, because binding
    /// this path is what makes a process **the** Terminal Checkout on this machine — the one the
    /// relay reaches and the extension is therefore talking to. It is not `@discardableResult`: a
    /// caller that has no use for it says so (`main.swift`'s headless server, which draws nothing and
    /// must not invent a revision anyway, D49).
    func start() throws -> LocalePublicationRight {
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

        guard var addr = makeUnixSockaddr(socketPath) else {
            throw ServerError.socketFailed("the path is too long: \(socketPath)")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketFailed(String(cString: strerror(errno))) }

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw ServerError.socketFailed(reason)
        }
        chmod(socketPath, 0o600)
        serverFD = fd
        boundIdentity = Self.identity(ofPathAt: socketPath)
        acceptQueue.async { [weak self] in self?.acceptLoop(serverFD: fd) }
        let right = LocalePublicationRight.mint()
        self.right = right
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
    func stop() {
        right?.relinquish()
        right = nil
        guard serverFD >= 0 else { return }
        if let boundIdentity, let now = Self.identity(ofPathAt: socketPath), now == boundIdentity {
            unlink(socketPath)
        }
        boundIdentity = nil
        close(serverFD)
        serverFD = -1
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
                resolved: AppLocalization.resolvedLocale(), role: .headless
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
