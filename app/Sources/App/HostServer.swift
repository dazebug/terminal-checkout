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
    private let acceptQueue = DispatchQueue(label: "terminal-checkout.accept")
    private let execQueue = DispatchQueue(label: "terminal-checkout.exec") // serializes terminal launches

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() throws {
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
        acceptQueue.async { [weak self] in self?.acceptLoop(serverFD: fd) }
    }

    func stop() {
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
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
                    let handle = try runInTerminal(
                        command: prepared.command, terminal: terminal,
                        injectsClaudeInput: !prepared.claudeInputs.isEmpty
                    )
                    timeline.step("\(terminal.rawValue) tab created")
                    if !prepared.claudeInputs.isEmpty {
                        // Watching the delivery can take minutes — waiting for claude to come up
                        // and the per-input retries both block — so the response goes back as soon
                        // as the tab is spawned and the watch runs outside the serial execQueue,
                        // which would otherwise hold up both that queue and Chrome's answer
                        DispatchQueue.global(qos: .utility).async {
                            deliverClaudeInputs(
                                prepared.claudeInputs, to: handle, timeline: timeline
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
