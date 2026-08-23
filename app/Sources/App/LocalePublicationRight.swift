import Core
import Foundation

// **The file is the boundary, because in Swift nothing smaller is.**
//
// `private` on a member covers the type *and its extensions in the same file*, so a `private`
// initialiser and a `private` mint are both reachable from `extension LocalePublicationRight { … }`
// written beside them — measured, not reasoned: both probes compile (round 22 review, and the round
// before it asserted the opposite behind a probe that used an unrelated declaration and therefore
// could not have found this).
//
// Access control cannot close that, so what moved is the file. The claim is now the one that holds:
// **nothing outside this file can produce a right, and inside it the only producer binds.** This
// file is short and contains nothing else, so "the same file" is a page somebody has to choose to
// edit rather than the whole server implementation. A producer added *here* is still possible and is
// the residual — it is what `private` means.
//
// `bindingSocket` is `internal`, and since round 24 that carries nothing: what it hands back names
// the path it bound, and only the canonical one publishes, so reaching the factory with a temporary
// name buys a right to that name and no more. `relinquish` is `internal` too, and giving a right up
// is the fail-closed direction.

/// **What a successful bind produced: the descriptor to accept on, and the right it is the reason
/// for.**
///
/// One value because they are one fact. They used to be two stored properties assigned six lines
/// apart, and a `stop()` landing between them relinquished nothing and closed the socket, after
/// which `start` went on to publish as the owner and arm an accept loop on a closed descriptor —
/// the process claiming the machine while nothing could reach it, which is the state the whole
/// ownership design exists to prevent (round 20 review).
struct BoundSocket {
    let fd: Int32
    let right: LocalePublicationRight
    /// Which file the bind created. Remembered because the path is a name that can come to mean
    /// something else, and a teardown that goes by the name alone deletes the socket the relay is
    /// now talking to (round 16 review).
    var identity: (dev: dev_t, ino: ino_t)?

    fileprivate init(fd: Int32, right: LocalePublicationRight) {
        self.fd = fd
        self.right = right
    }
}

/// **The right to publish a locale, as a thing you have rather than a question you ask.**
///
/// Round 14 bound the launch publisher to the socket and left the picker unbound; round 15 made both
/// ask one type, and the answer was a process-global boolean. A boolean is a *convention*: it says
/// what somebody recorded, not what anybody holds, and the launch writer went on publishing without
/// consulting it while a comment at the call site declared the rule for both (round 16 review). So
/// the answer is a value now.
///
/// **And the bind happens here** (round 20 review). Round 19 checked the descriptor a caller handed
/// in, which stops a mistake and not a producer: `mint` was `fileprivate`, so a second declaration
/// in this file could bind a socket of its own, pass perfectly valid arguments and come away with a
/// right, while the sentence here claimed no call site anywhere could. The operation moved to where
/// the invariant lives instead — `mint` is `private`, and the only way to reach it is
/// `bindingSocket(at:)`, which performs the `bind` and the `listen` itself.
///
/// **The sentence that stood here — "a value nobody can make" — was measured false and is now the
/// one at the top of this file.** `private` does not exclude an extension written beside the type,
/// so what bounds a producer is the file, not the keyword (round 22 review).
///
/// **And a right says which socket, because binding *a* socket is not owning *the* one.** That
/// sentence used to end at "reaching the factory means performing the bind", which was true and
/// insufficient (round 24 review): `bind` is exclusive *per path*, so a right that did not carry its
/// path was a right to nothing in particular — any file in the module could bind a temporary name,
/// receive a right, and hand it to the picker. Worse, minting gave up the previous holder, so that
/// right **unseated the real server's** and the process the relay actually reaches could no longer
/// publish.
///
/// So the path is part of the value, holders are kept per path, and publication asks for the
/// canonical one (`Settings.publishInteractively`). A right for a temporary name is still a real
/// right to a real bind — it simply publishes nothing and unseats nobody.
///
/// **This is deliberately not a fifth tightening of visibility.** Four rounds went any file → the
/// same file → a same-file extension → the whole module, and each one moved the producer rather than
/// removing it. What a value *attests* is the axis that closes it: `bindingSocket` can stay reachable
/// because what it hands back is now specific.
///
/// **Ownership lasts exactly as long as the socket does.** The path can be taken over: this process
/// stops listening, another binds the same path, and from then on the relay is talking to that one.
/// A right that outlived its socket would let this process go on moving a generation the extension
/// orders by while nothing can reach it. So `stop()` gives the right up, and a right that has been
/// given up runs no write (`whileHeld`) — the same behaviour as the headless reader, which is what a
/// process that no longer owns the machine's socket is.
final class LocalePublicationRight {
    private static let lock = NSLock()
    /// One live right per path. It was a single holder, which is what let a bind of *any* name unseat
    /// the real server's right — two binds of different paths are not competitors for anything, and a
    /// bind of the same path cannot happen while the first is held (round 24 review).
    private static var holders: [String: LocalePublicationRight] = [:]

    /// What this process holds **for the socket the relay reaches**. Nil in an instance that lost the
    /// bind (`alreadyRunning`), in a process that never started a server, after the socket has been
    /// given up, and for a right bound to any other name. It is read rather than passed in the two
    /// places that cannot be handed a value — the picker and the window that draws it — and reading
    /// it is not a way around anything: **what it answers is whether we hold the one that counts.**
    static var current: LocalePublicationRight? {
        lock.lock()
        defer { lock.unlock() }
        return holders[defaultSocketPath()]
    }

    /// The name this right's bind holds. Not decoration: it is the difference between "a socket" and
    /// "the socket", and publication asks for it.
    let path: String

    private var held = true

    private init(path: String) {
        self.path = path
    }

    /// **The bind, and the right it is the reason for.**
    ///
    /// The only producer **in the program**. `mint` below is `private`, which puts it out of reach of
    /// every other file — including an `extension LocalePublicationRight` written in one, measured.
    /// Inside this file it is reachable, and that is what the note at the top is about.
    ///
    /// It is `internal` because `HostServer` is in another file, and that no longer has to carry the
    /// invariant: the right it hands back names the path it bound, so reaching this with a temporary
    /// name yields a right that publishes nothing. What stays out of reach is the making of one
    /// without a bind at all — `mint` and the initialiser are `private`, and this file is the
    /// boundary that means something (see the note at the top).
    static func bindingSocket(at path: String) throws -> BoundSocket {
        guard var address = makeUnixSockaddr(path) else {
            throw HostServer.ServerError.socketFailed("the path is too long: \(path)")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw HostServer.ServerError.socketFailed(String(cString: strerror(errno)))
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw HostServer.ServerError.socketFailed(reason)
        }
        return BoundSocket(fd: fd, right: mint(for: path))
    }

    /// **The previous right stops being one before the new one is visible.**
    ///
    /// It used to be `holder = right; unlock; previous?.relinquish()`, and the comment above it said
    /// the previous right was given up *first*. It never was: between the unlock and the relinquish
    /// **both rights report held**, and the old one could enter `whileHeld` and write. Not a doc
    /// gone stale — a doc that described an order the code had never had, in the function the round
    /// before this one rewrote (round 20 review).
    ///
    /// **Only a right for the same path is given up.** A single holder meant that binding any name at
    /// all unseated whoever held the canonical one — a denial of publication dressed as a handover
    /// (round 24 review). Two binds of different paths are not two answers to one question; they are
    /// answers to different ones.
    private static func mint(for path: String) -> LocalePublicationRight {
        lock.lock()
        defer { lock.unlock() }
        holders[path]?.giveUp()
        let right = LocalePublicationRight(path: path)
        holders[path] = right
        return right
    }

    /// Still ours? False once the socket it came from has been let go. **A question, and a question
    /// is not a permission**: a caller that means to write wants `whileHeld`, where the answer
    /// cannot go stale between being given and being acted on.
    var isHeld: Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return held
    }

    /// Whether this right has been superseded **and still reports held** — the state this type says
    /// cannot exist.
    ///
    /// One acquisition of the class lock, and that is the whole reason it exists: asking "who is the
    /// holder" and "is this one still held" as two questions takes the lock twice, and a legitimate
    /// handover landing between them looks exactly like the violation. No production caller; what it
    /// makes observable is the type's central claim.
    ///
    /// **Two terms, not three.** It also required a successor to exist, which asks a narrower
    /// question than the one being posed: a handover that left the old right held with *no* holder
    /// passed the predicate while `whileHeld` would still have written (round 22 review). Whether
    /// somebody replaced it is not part of "this right is live and is not the holder".
    static func supersededButStillHeld(_ right: LocalePublicationRight) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return right.held && holders[right.path] !== right
    }

    /// **Runs `body` under the lock that decides whether this right is still held, and only while it
    /// is.**
    ///
    /// The check and the write used to sit under **different** locks: `LocaleState.publish` asked
    /// `mayWrite` — this class's lock — and then wrote under its own, so `HostServer.stop()` could
    /// give the right up in between. What lands then is not "one stale write". `published()` is a
    /// read-modify-write against a shared `UserDefaults`, and the process that loses the socket in a
    /// **language restart** is exactly the process that can still be inside the write. A write
    /// arriving at the new owner's epoch leaves the extension ordered by an epoch it has already
    /// accepted while the value under it is the old language — permanent until something else
    /// publishes, in the scenario this feature was built for.
    ///
    /// **The recorded reason for leaving it open did not survive being tried.** It was that merging
    /// them "would mean teardown taking the publication lock"; teardown takes only this one, and
    /// `LocaleState.commit` is the single path that holds both — always in the order writeLock →
    /// this one. With one order there is no inversion to have.
    ///
    /// nil is a **report** and not an absence: it says the body did not run. That is what lets a
    /// caller tell a publication that happened from one that did not, which is the other half of
    /// the same question.
    func whileHeld<T>(_ body: () -> T) -> T? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard held else { return nil }
        return body()
    }

    /// Given up with the socket. Idempotent, for the reason `giveUp` gives. `internal` because the
    /// teardown that calls it is in another file; giving a right up is the fail-closed direction, so
    /// nothing is lost by anyone being able to.
    func relinquish() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        giveUp()
    }

    /// The same thing **with the class lock already held**, which is the only reason it exists
    /// separately: `NSLock` is not recursive, and a reader's first instinct inside `mint` is to call
    /// `relinquish` — which deadlocks. Idempotent, and it clears **this path's** holder only if that
    /// is still this one, so a right superseded by a later bind of the same name does not take the
    /// newer one down with it, and a right for another name never touches it at all.
    private func giveUp() {
        held = false
        if Self.holders[path] === self { Self.holders[path] = nil }
    }
}
