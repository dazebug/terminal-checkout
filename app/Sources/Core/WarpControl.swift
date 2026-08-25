import ApplicationServices
import Foundation

// MARK: - Tab Config
// This is the only way to open a new tab in Warp and run a command in it: Warp does not support AppleScript (no .sdef in the bundle, no NSAppleScriptEnabled in Info.plist), warpctrl is disabled by default on Stable, and there is no CLI that sends text to a pane (nothing like `wezterm cli send-text`) — all measured.

/// Every request uses a different name. A fixed name broke two things at once:
/// ① a user Tab Config of the same name gets silently overwritten
/// ② Warp reads the file a little after `open` has returned (measured 0.5∼0.7s until the pane appears) — if the next request overwrites it in that gap, one of the two tabs shows the other's command
/// Splitting the names makes both problems disappear together, through the property that one file belongs to one request. In exchange, the file is deleted once the run is done so it does not pile up in the `+` menu (`runInWarp`), and whatever is left behind because the app died first gets reclaimed by the next run (`reclaimStaleWarpTabConfigs`).
public let warpTabConfigPrefix = "terminal-checkout-"

/// The fixed name early builds of this branch used — kept only as a reclaim target.
let warpTabConfigLegacyStem = "terminal-checkout"

/// The mark that identifies a file as generated. It is the last check before deleting, and it is there to keep a user file from being removed — a purpose, not a guarantee: `removeWarpTabConfigIfOurs` below documents the window in which one still could be.
///
/// **This token is a permanent machine protocol: it will not change again.** It carries no natural
/// language on purpose, so no future localization can have a reason to touch it. `uninstall.sh`
/// greps for it and `warpTabConfigIsOurs` matches it — both against the **whole first line**, so a
/// file that merely starts with it stays the user's — and those three copies have to stay
/// byte-identical, since a divergence means files nobody deletes. Anything a human should read goes
/// on the line **below** it (`warpTabConfigTOML`), where translating it is harmless.
public let warpTabConfigHeader = "#!terminal-checkout/tab-config/v1"

/// The header earlier builds wrote, kept **only** so their files stay reclaimable. It is Korean,
/// which is exactly why the token above replaced it.
///
/// **Rollback is forward-only, and that is accepted rather than solved** (D25): an older binary
/// cannot recognise a file written with the new token, so rolling back leaves those files in
/// `~/.warp/tab_configs/` for nobody to collect. The damage is bounded to clutter in Warp's `+`
/// menu — no data is lost — which is why it is documented instead of engineered around.
///
/// Removing this constant is safe only once no user can still be holding a file an older build
/// wrote. There is no signal that says so, so the trigger is a deliberate one: drop it in the first
/// release after the app gains a way to know its own upgrade history, or never.
public let warpTabConfigLegacyHeader = "# Terminal Checkout이 자동 생성합니다"

public func warpTabConfigStem(token: String) -> String { warpTabConfigPrefix + token }

/// Only the Stable channel is looked at — other channels (Preview and so on) diverge starting from this very directory, at `~/.warp-<channel>`.
public func warpTabConfigDirectory() -> String {
    (NSHomeDirectory() as NSString).appendingPathComponent(".warp/tab_configs")
}

public func warpTabConfigPath(stem: String) -> String {
    (warpTabConfigDirectory() as NSString).appendingPathComponent("\(stem).toml")
}

public func warpTabConfigURL(stem: String) -> String { "warp://tab_config/\(stem)" }

/// Is this a file name we may reclaim — our prefix plus a hex token, or the old fixed name.
public func warpTabConfigFileIsOurs(name: String) -> Bool {
    guard name.hasSuffix(".toml") else { return false }
    let stem = String(name.dropLast(".toml".count))
    if stem == warpTabConfigLegacyStem { return true }
    guard stem.hasPrefix(warpTabConfigPrefix) else { return false }
    return isOurRequestToken(stem.dropFirst(warpTabConfigPrefix.count))
}

/// The contents are checked too — a user file whose name happens to collide must not be deleted.
///
/// Both headers count. The legacy one is not a fallback for our own writes (we never write it any
/// more) but for **files already on users' disks**: dropping it here would strand every Tab Config
/// an earlier build left behind.
public func warpTabConfigIsOurs(contents: String) -> Bool {
    // The token is matched **whole line, exactly**. A prefix match reads `…/v1` followed by
    // anything as ours — `…/v10`, the shape the next format version takes, and any user line that
    // happens to start the same way — and the verdict's one job is to keep a user file from being
    // deleted. We had made this exact match possible ourselves by moving the explanation onto its
    // own line and then kept matching by prefix (round 5 review).
    if contents.prefix(while: { $0 != "\n" }) == warpTabConfigHeader { return true }
    // The legacy header keeps its prefix match because earlier builds wrote the explanation on the
    // **same** line, so there is no exact string on those disks to match.
    return contents.hasPrefix(warpTabConfigLegacyHeader)
}

/// Escaping for a TOML basic string. Control characters cannot be carried literally and have to become escape sequences — let one through and Warp fails to parse the file, so the tab does not open at all.
public func escapeForTOMLBasicString(_ text: String) -> String {
    var out = ""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\\": out += #"\\"#
        case "\"": out += #"\""#
        case "\u{08}": out += #"\b"#
        case "\u{09}": out += #"\t"#
        case "\u{0A}": out += #"\n"#
        case "\u{0C}": out += #"\f"#
        case "\u{0D}": out += #"\r"#
        default:
            if scalar.value < 0x20 || scalar.value == 0x7F {
                out += String(format: #"\u%04X"#, scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    return out
}

/// A single-pane Tab Config that runs the commands in order.
/// It carries no `directory` key, to match iTerm2 and WezTerm — the pane starts in the default cwd
/// and the command's own entry clause does the moving (`{cd}`, which the app renders from its base
/// directory setting).
/// It declares no `[params.*]` either. Declaring parameters pops a fill-in modal on open, and the
/// command doesn't run until the user answers. Undeclared, a `{{...}}` inside a command is passed
/// to the shell as-is, with no substitution and no modal (measured) — which is why `{{` needs no
/// defense of its own.
public func warpTabConfigTOML(commands: [String]) -> String {
    let list = commands.map { "\"\(escapeForTOMLBasicString($0))\"" }.joined(separator: ", ")
    return """
    \(warpTabConfigHeader)
    # Generated by Terminal Checkout; deleted once the tab has opened.
    name = "\(appDisplayName)"

    [[panes]]
    id = "main"
    type = "terminal"
    commands = [\(list)]

    """
}

// MARK: - Launching the injection helper

/// The name of the executable that sits next to the relay inside the app bundle (`app/build.sh` copies it).
let warpHelperExecutableName = "terminal-checkout-warp-helper"

/// The helper executable's path: inside `Contents/MacOS/` for the app, next to the executable for tests and the CLI.
/// nil when it cannot be found — the command then runs on its own and claude input is given up.
func warpHelperExecutablePath() -> String? {
    guard let directory = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
    let path = directory.appendingPathComponent(warpHelperExecutableName).path
    return FileManager.default.isExecutableFile(atPath: path) ? path : nil
}

/// Turns it into a single shell word. The app bundle path contains a space (`Terminal Checkout.app`), so without quoting the shell splits it into two words and the helper never starts.
public func shellSingleQuoted(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}

/// The paths are absolute and single-quoted — nothing in the user's shell (PATH, functions, aliases)
/// can change what this line runs.
///
/// The third word is the **deadline**: seconds since the epoch, past which the helper does not take
/// its address. We write this line, so what the helper is told at birth is ours to choose, and this
/// is the one thing it needs that nothing later can take away from it (round 23 review).
public func warpHelperCommand(
    executable: String, socketPath: String, deadline: Date = Date().addingTimeInterval(warpHelperClaimWindow)
) -> String {
    let seconds = String(Int(deadline.timeIntervalSince1970))
    return "\(shellSingleQuoted(executable)) \(shellSingleQuoted(socketPath)) \(seconds)"
}

/// Can the injection helper be launched — is the executable in the bundle, and does the socket
/// path stay under the 104-byte limit? The length depends on the temp directory and the token is
/// always 8 characters, so measuring with any token gives the same answer.
public func warpInjectionHelperIsReady() -> Bool {
    warpHelperExecutablePath() != nil && warpHelperSocketPath(token: warpHelperToken()) != nil
}

/// Is this the token **we** put in a name? One rule for every name we reclaim, because the
/// reclaim side used to be wider than the creation side: `%08x` writes exactly eight lower-case
/// ASCII hex digits, so anything else — upper case, a different length, a Unicode digit — is a
/// name we never wrote, and deleting one of those is deleting somebody else's file (round 8).
func isOurRequestToken(_ token: Substring) -> Bool {
    token.count == requestTokenLength && token.allSatisfy(\.isASCIIHexLower)
}

/// The width of `%08x`, which is what `warpHelperToken()` formats.
let requestTokenLength = 8

extension Character {
    /// A character our own `%08x` tokens can contain. `isHexDigit` and `isNumber` are **Unicode**
    /// predicates — Arabic-Indic digits and full-width forms satisfy them — and every place that
    /// decides "is this name one we wrote, and may we delete it" needs the ASCII answer instead
    /// (reproduced: `tc-prompt-١٢٣٤abcd` counted as ours).
    var isASCIIHexLower: Bool { isASCII && isHexDigit && !isUppercase }
}

/// Drawn fresh for every run — with a fixed name we would either attach to a dead socket file left by an earlier run, or send input to an earlier helper that is still alive in another pane.
public func warpHelperToken() -> String {
    String(format: "%08x", UInt32.random(in: .min ... .max))
}

/// Is this a socket file name we may reclaim — our prefix plus a hex token.
///
/// Both names a helper can leave behind are ours: the advertised one, and the staging one it binds
/// before it is entitled to the advertised one (`warpHelperStagingPath`). A helper killed between
/// `listen` and the claim leaves the second, and a reclaim that only knew the first would leave it
/// in `/tmp` for good.
/// And the pin, which is not a socket and so is not one of the two names above.
public func warpHelperPinFileIsOurs(name: String) -> Bool {
    guard name.hasPrefix(warpHelperSocketPrefix), name.hasSuffix(warpHelperPinSuffix) else { return false }
    return isOurRequestToken(
        name.dropFirst(warpHelperSocketPrefix.count).dropLast(warpHelperPinSuffix.count)
    )
}

public func warpHelperSocketFileIsOurs(name: String) -> Bool {
    guard name.hasPrefix(warpHelperSocketPrefix) else { return false }
    for suffix in [warpHelperAdvertisedSuffix, warpHelperStagingSuffix] where name.hasSuffix(suffix) {
        return isOurRequestToken(name.dropFirst(warpHelperSocketPrefix.count).dropLast(suffix.count))
    }
    return false
}

public let warpHelperSocketPrefix = "tcw-"
/// The name the app writes into the Tab Config and later talks to.
public let warpHelperAdvertisedSuffix = ".sock"
/// The name a helper listens on until it is allowed to answer to the advertised one. Shorter than
/// the advertised suffix on purpose: a path that fits `sun_path`'s 104 bytes then has a staging
/// name that fits too, so the length check on the advertised path answers for both.
public let warpHelperStagingSuffix = ".pre"
/// The file the app links from to take an address back (`warpHelperPinPath`). Not a socket and
/// never bound, so it needs no room in `sun_path`.
public let warpHelperPinSuffix = ".pin"

/// The first candidate directory whose path fits in sun_path's 104 bytes. nil when none of them fits.
public func warpHelperSocketPath(token: String, directories: [String]) -> String? {
    for directory in directories {
        let path = (directory as NSString)
            .appendingPathComponent("\(warpHelperSocketPrefix)\(token)\(warpHelperAdvertisedSuffix)")
        if makeUnixSockaddr(path) != nil { return path }
    }
    return nil
}

/// A temporary directory is used because its path is short, which leaves headroom against sun_path's 104-byte limit.
/// The OS is not relied on to clean up what is left behind — when the helper ends on SIGKILL its `unlink` never runs, so the next run reclaims dead sockets itself (`reclaimDeadWarpHelperSockets`).
public func warpHelperSocketPath(token: String) -> String? {
    warpHelperSocketPath(token: token, directories: [NSTemporaryDirectory(), "/tmp"])
}

// MARK: - The advertised address has one owner, and the kernel decides which

// A helper is created by a line this app writes into a Tab Config, and it is created **late**: the
// launch can take fifteen seconds and Warp brings the pane up 0.5∼0.7s after `open` returns
// (measured). So the app can decide to go away between admitting a request and that helper being
// born, and the farewell it sends on the way out then reaches a socket nobody is listening on.
// Round 16 recorded that as a residual; round 17's review found the residual understated — the
// window opens at `record`, not at `open`.
//
// It is closed by making the two sides race for **one name**, one operation each, with both
// outcomes safe.
//
// **The app occupies the name with the same operation the helper claims it with — `link`** (round
// 21 review). `bind` and then `mkdir` were each better than the last and each left the same shape of
// gap, which is what this decides against:
//  - `bind` needs a descriptor, so it failed where `socket()` failed, and every such failure read as
//    "the helper won" — a farewell to nobody while the delayed helper's `link` still succeeded;
//  - `mkdir` needs no descriptor but it does need an **inode**, and `link` reuses the socket's. The
//    previous round wrote that sliver down and then took the unsafe branch inside it: an inode
//    shortage answered `.failed`, which sends no farewell, while the helper's `link` went through.
//    "Shares some failure modes" had been allowed to stand for "shares all of them".
// Linking from a file the app already holds removes the argument instead of narrowing it: both sides
// create a directory entry in the **same parent** and neither allocates an inode, so *the app could
// not occupy* implies *the helper cannot claim* — **while the source entry and the filesystem
// conditions are unchanged between the two calls**. That qualifier is not decoration (round 23
// review): the same two syscalls at different moments are not the same outcome, and this file
// documents the counterexample a few paragraphs down — a same-uid process deleting the pin makes the
// app's `link` answer `ENOENT` while the helper's later one succeeds. Neither side retries a
// transient either. What the construction removes is the *class* of divergence that came from the
// two operations being different operations; what remains is named as residual 5 in the helper's
// preamble. The file to link from is made
// when the helper is registered rather than when the app is leaving, which is what keeps
// termination-time pressure out of the path (`warpHelperPinPath`).
//
// Measured with throwaway probes that are not in the repository — the findings below are the whole
// record of them, so nothing here is a pointer to go and read:
//  - `link` onto a name that already exists is refused with `EEXIST`, either way round, and a
//    *listening* socket reached through a hard link accepts connections normally — so the helper can
//    bind privately, listen, and only then put itself where the app is looking;
//  - the two links fail together: parent missing is `ENOENT` for both, parent read-only `EACCES` for
//    both, and the advertised name ends up carrying the source's inode (`nlink` 2), so nothing new
//    is allocated on either side;
//  - `rename` overwrites its destination and is therefore useless here — the helper would take back
//    an address the app had already occupied.
// What is lost is `EADDRINUSE`'s specificity, and what replaces it is narrower than it looks:
// `EEXIST` says the name is **occupied** and nothing more — not who by. That is why the value says
// `occupied` and the farewell is best effort (measured: connecting to a non-socket is `ENOTSOCK`,
// not a hang).

/// The name a helper binds before it is entitled to answer on the advertised one.
public func warpHelperStagingPath(advertised: String) -> String {
    (advertised as NSString).deletingPathExtension + warpHelperStagingSuffix
}

/// The file the app links from when it takes an address back.
///
/// It sits beside the advertised name so that the occupation and the helper's claim are entries in
/// the same directory — that is what makes their failures the same failures. It is created when the
/// helper is registered, because a source made at termination would put the allocation this design
/// exists to avoid back into the moment that must not fail.
public func warpHelperPinPath(advertised: String) -> String {
    (advertised as NSString).deletingPathExtension + warpHelperPinSuffix
}

/// What is written inside the pin, and therefore inside the occupied name — they are two names for
/// one inode, so proving one proves the other.
///
/// It exists because the sweep that removes them has to tell our file from a file somebody else put
/// at the same name, and a name cannot do that: the socket sweeps are narrow on purpose ("anyone can
/// drop a regular file or a symlink under the same name"), and widening one to regular files would
/// have given that away. Content is how `warpTabConfigIsOurs` already answers the same question. A
/// language-neutral token, for the reason D25 gives — nothing here is ever translated.
public let warpHelperPinMarker = "terminal-checkout/warp-helper-pin v1\n"

/// Makes that file. Called once per Warp request that schedules claude input, next to the register
/// entry it belongs to.
///
/// False means the request is refused — `runInWarp` throws on it, because a helper whose address
/// cannot be taken back is the defect this whole mechanism exists for. **The comment here used to
/// say the caller runs anyway, and it was born false in the commit that made the caller refuse**
/// (round 23 review): both lines were written together, so no re-reading of what the change
/// *falsified* could have caught it.
///
/// **A partial pin is worse than none**, so a failed write takes the file with it: the sweep removes
/// only files carrying the whole marker, so a half-written one would be collected by nothing, ever.
/// What survives that is a process that dies between the `write` and the `unlink` — the file is then
/// a leak this design does not collect, and that is the residual rather than a race.
@discardableResult
public func createWarpHelperPin(forAdvertised advertised: String) -> Bool {
    let path = warpHelperPinPath(advertised: advertised)
    let fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    guard writeAll(fd: fd, data: Data(warpHelperPinMarker.utf8)) else {
        unlink(path)
        return false
    }
    return true
}

/// Removes one we have just made and are giving up on — the registration threw, so nothing was
/// launched and nothing can claim.
///
/// It goes through the same verifier the sweep uses rather than a raw `unlink`: between making the
/// file and this line a same-uid process can put something else at that name, and "we made it a
/// moment ago" is not the same fact as "this is it".
public func removeWarpHelperPin(forAdvertised advertised: String) {
    removeWarpHelperFileIfOurs(path: warpHelperPinPath(advertised: advertised))
}

/// **The helper's half**, taken after it is already listening — which is why the advertised name
/// never exists in a state where a connection to it would be refused.
///
/// False means the advertised name was already occupied — by the app taking it back before the pane
/// came up, which is the case this exists for, or by anything else at that name — and then this
/// helper must not serve. The staging name is dropped either way: on success the socket has the
/// advertised name, on failure this process is leaving, and in both cases the socket itself is held
/// by the fd rather than by a name.
///
/// `errno` is put back after the `unlink` so the caller can still say *why* it lost — `EEXIST` is
/// occupancy and anything else is not, and a diagnostic that could not tell them apart would report
/// a vanished temporary directory as a decision the app made.
public func claimWarpHelperAddress(from staging: String, as advertised: String) -> Bool {
    let claimed = link(staging, advertised) == 0
    let failure = errno
    unlink(staging)
    if !claimed { errno = failure }
    return claimed
}

/// **What became of an address the app tried to take back on its way out.**
///
/// Three, and the third is the point (round 19 review, P0). The answer used to be a `Bool` whose
/// false covered both "a helper already has it" and "this process could not take it", and every
/// false became an address to say goodbye to. The comment defending that argued the cost of a
/// farewell to nobody is a refused connection — true when the outcomes are two. They are three: if
/// nothing was withdrawn *and* nobody holds the name, the farewell reaches nobody, the delayed
/// helper's `link` succeeds, and it outlives the app.
public enum WarpHelperAddressWithdrawal: Equatable {
    /// Taken. No helper can ever answer there, and there is nothing to dismiss.
    case withdrawn
    /// **Something is at that name.** Not "a helper is listening": `EEXIST` is returned for a helper
    /// socket, for a leftover from an earlier run, and for anything else the same uid put there, and
    /// nothing in an errno separates them (round 21 review). The farewell is attempted because the
    /// occupant may be a helper; a refused connection is the expected outcome when it is not.
    case occupied
    /// Neither, and **this is not an address to say goodbye to**. What it is instead is a fact to
    /// report: this process could not act, and saying goodbye would record a dismissal that did not
    /// happen. Since the occupation became a `link`, this also means the helper cannot claim — the
    /// two operations fail together (see the section preamble).
    case failed(String)
}

/// Why a claim was refused, in words that are true for **that** errno.
///
/// It lives here rather than at the one `fail(...)` in the helper because a diagnostic nobody can
/// exercise is a diagnostic that goes wrong quietly: an earlier one named the withdrawal for every
/// errno, so a vanished temporary directory was reported as a decision the app had made (round 19
/// review) — the class this work has swept since round 1, committed by the round that swept it.
///
/// **`EEXIST` says occupied, not who by** (round 21 review). The app taking the address back is one
/// way the name comes to be occupied; a leftover from an earlier run and anything else with this
/// uid are others, and this process cannot tell them apart from an errno. The sentence says what is
/// known.
public func warpHelperClaimFailure(_ code: Int32) -> String {
    let reason = String(cString: strerror(code))
    return code == EEXIST
        ? "the advertised address is already occupied (\(reason)) — the app takes it that way when it goes away, and it is not the only thing that can"
        : "the advertised address could not be taken (\(reason))"
}

/// **The app's half**, taken as it goes away: occupy the address the helper has not taken yet, so
/// that it never can.
///
/// `link` from the pin, for the reason in the section preamble: it is the same operation the helper
/// claims with, into the same parent, and neither allocates an inode — so **whatever stops this
/// stops that**. `mkdir` was the previous answer and left a sliver it named and then took the unsafe
/// branch inside; there is no enumeration of shared failure modes here to be incomplete.
///
/// A missing pin is itself a `.failed`, with `ENOENT` — and the same `ENOENT` is what the helper's
/// `link` would get if the parent were gone, which is the only way the pin can be missing without
/// somebody having removed it. Removing it is a same-uid act and is residual 5 in the helper's
/// preamble.
public func withdrawWarpHelperAddress(_ advertised: String) -> WarpHelperAddressWithdrawal {
    guard link(warpHelperPinPath(advertised: advertised), advertised) != 0 else { return .withdrawn }
    let reason = errno
    guard reason != EEXIST else { return .occupied }
    return .failed(String(cString: strerror(reason)))
}

// MARK: - Install detection and the process tree

/// The Warp app bundle. Only the standard locations are looked at, so a LaunchServices lookup (AppKit) never enters Core — the app and Core share this one function, which is what keeps "installed according to the settings, not found when running" from happening.
public func findWarpAppBundle() -> String? {
    let candidates = [
        "/Applications/Warp.app",
        (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Warp.app"),
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0) }
}

/// The absolute path of the Warp executable. It has to match ps's command column exactly for the GUI process to be identified, so the executable name is read from the bundle's Info.plist (on Stable it is `stable`).
public func findWarpExecutable() -> String? {
    guard let bundle = findWarpAppBundle() else { return nil }
    let infoPath = (bundle as NSString).appendingPathComponent("Contents/Info.plist")
    guard let name = NSDictionary(contentsOfFile: infoPath)?["CFBundleExecutable"] as? String
    else { return nil }
    let executable = (bundle as NSString).appendingPathComponent("Contents/MacOS/\(name)")
    return FileManager.default.isExecutableFile(atPath: executable) ? executable : nil
}

/// Picks the Warp GUI process's pid out of `ps -axo pid=,ppid=,command=` output.
/// The GUI process is the parent of `terminal-server` (measured: `stable terminal-server --parent-pid=<gui>`).
/// The GUI itself starts with no arguments, so the arguments are what tells them apart — without looking at them, the GUI's parent (launchd) gets named as Warp.
public func warpGUIPIDs(psOutput: String, executablePath: String) -> [Int] {
    var pids: [Int] = []
    for line in psOutput.split(separator: "\n") {
        // "pid ppid command…" — the command contains spaces, so only the first two gaps are split on
        let parts = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
        guard parts.count == 3, let ppid = Int(parts[1]) else { continue }
        let command = parts[2].trimmingCharacters(in: .whitespaces)
        guard command.hasPrefix(executablePath + " ") else { continue }
        let args = command.dropFirst(executablePath.count + 1).split(whereSeparator: { $0.isWhitespace })
        if args.first == "terminal-server", !pids.contains(ppid) { pids.append(ppid) }
    }
    return pids
}

/// The Warp GUI processes currently running.
func currentWarpGUIPIDs() -> [Int] {
    guard let executable = findWarpExecutable(),
          let ps = try? runProcess("/bin/ps", ["-axo", "pid=,ppid=,command="], timeout: 5),
          ps.status == 0
    else { return [] }
    return warpGUIPIDs(psOutput: ps.stdout, executablePath: executable)
}

// MARK: - Accessibility (reading the screen)
// Delivering input has nothing to do with Accessibility — the helper puts bytes only into our own tty.
// Accessibility is a best-effort signal used solely to check "did claude draw that input in its input box".

/// The Accessibility permission state — queried without raising a prompt.
public func accessibilityIsTrusted() -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: false] as CFDictionary)
}

/// Raises the Accessibility permission prompt (true straight away when it is already granted).
/// Unlike the Automation permission, this prompt does not grant anything on the spot — it only points at System Settings — so the outcome has to be confirmed by asking `accessibilityIsTrusted()` again.
@discardableResult
public func requestAccessibilityPrompt() -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
}

/// The screen text of Warp's focused pane. nil without the permission, or without Warp.
///
/// What gets read is "the focused pane in that window", so there is no guarantee it is ours — a Warp window's AX children are a single `AXTextArea` plus three window buttons, with no tab bar and no pane identifier, and switching tabs reuses the same AX element (measured). It is nevertheless safe because **input does not travel this path**: typing and submitting go through the helper into our own tty alone, so the worst that reading someone else's pane can do is "the pane proof and the reflection check fail, we retry, and nothing gets submitted".
public func warpScreenText() -> String? {
    // Timed from the first line, not from after the guard: what the poll interval has to cover is
    // the **whole call** — the TCC trust check, the `ps` that finds Warp's pids, and the AX walk
    let started = Date()
    defer { warpScreenReadCost.record(Date().timeIntervalSince(started)) }
    guard accessibilityIsTrusted() else { return nil }
    // ps is called again for every window read — the reflection check runs five times at 0.4s intervals, so the cost does not show, and a cache would hold on to a dead pid after Warp restarts
    for pid in currentWarpGUIPIDs() {
        if let text = warpFocusedPaneText(pid: pid_t(pid)) { return text }
    }
    return nil
}

/// What one Accessibility screen read costs, for the first few reads of a process.
///
/// Round 10 set `screenPollInterval` (0.15s) so that every known reader stays under half the
/// interval — osascript 59ms, wezterm cli 14ms, ps+stty 9ms — and had to **assume** Warp's read was
/// "no cheaper than osascript", because measuring it needs Warp running and the permission granted.
/// Both hold now, so the reads report themselves. If this turns out to be hundreds of milliseconds,
/// the poll interval is resting on a false premise and the next round has its input.
///
/// Only the first reads are logged: the first one carries process-attach and AX-tree warm-up, the
/// next few are the steady state, and after that it would be noise on every poll. The normal log
/// level, not `debug` — `Logger.debug` is not persisted, so `log show` would not have it when the
/// number is read back.
private let warpScreenReadCost = ScreenReadCostLog(reportsWanted: 5)

private final class ScreenReadCostLog: @unchecked Sendable {
    private let lock = NSLock()
    private let reportsWanted: Int
    private var reported = 0

    init(reportsWanted: Int) { self.reportsWanted = reportsWanted }

    func record(_ elapsed: TimeInterval) {
        lock.lock()
        guard reported < reportsWanted else { return lock.unlock() }
        reported += 1
        let index = reported
        lock.unlock()
        checkoutLog("Warp screen read #\(index) took \(Int((elapsed * 1000).rounded()))ms")
    }
}

/// Reads the pane screen text from the focused window of the given Warp process.
private func warpFocusedPaneText(pid: pid_t) -> String? {
    let app = AXUIElementCreateApplication(pid)
    guard let window = axElement(app, kAXFocusedWindowAttribute as String)
        ?? axElement(app, kAXMainWindowAttribute as String)
    else { return nil }
    return firstTextAreaValue(in: window, depth: 3)
}

private func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let raw = value, CFGetTypeID(raw) == AXUIElementGetTypeID()
    else { return nil }
    return (raw as! AXUIElement) // swiftlint:disable:this force_cast
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
    else { return nil }
    return value as? String
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
    else { return [] }
    return (value as? [AXUIElement]) ?? []
}

private func firstTextAreaValue(in element: AXUIElement, depth: Int) -> String? {
    guard depth > 0 else { return nil }
    for child in axChildren(element) {
        if axString(child, kAXRoleAttribute as String) == (kAXTextAreaRole as String),
           let value = axString(child, kAXValueAttribute as String) {
            return value
        }
        if let nested = firstTextAreaValue(in: child, depth: depth - 1) { return nested }
    }
    return nil
}

// MARK: - Reclaiming
// The normal paths clean up after themselves: the helper removes its socket on `bye`, on the pane closing, and on any catchable signal, and `runInWarp` deletes the Tab Config once the tab has opened. What skips all that is SIGKILL, a power cut, or an app crash.
// The next run sweeps up that remainder — on the condition that it **never touches anything alive**.

/// Deletes helper socket files whose owner has died. There are three conditions because any one of them alone would delete somebody else's file:
///  ① the name is ours — but anyone can put a **regular file or a symbolic link** of the same name there
///  ② `lstat` says it is a socket — it does not follow links, so whatever a link points at is safe too
///  ③ it does not accept a connection — one that does belongs to a live helper
/// Freshly created files are skipped because connections are refused during the brief moment between `bind` and `listen` — deleting in that window removes a live helper's socket and the whole delivery disappears.
/// The TOCTOU between ③ and `unlink` cannot be removed (deleting is only possible by path). It is narrowed by doing one more `lstat` immediately before deleting, and a helper born in that gap is kept out by ①'s random token differing, so it never uses the same path.
func reclaimDeadWarpHelperSockets(
    in directories: [String] = [NSTemporaryDirectory(), "/tmp"], youngerThan grace: TimeInterval = 60
) {
    for directory in Set(directories) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
        for name in names where warpHelperSocketFileIsOurs(name: name) {
            let path = (directory as NSString).appendingPathComponent(name)
            guard isUnixSocketFile(path),
                  let modified = fileModificationDate(path),
                  Date().timeIntervalSince(modified) > grace
            else { continue }
            if let fd = connectToUnixSocket(path: path) {
                close(fd)
                continue
            }
            guard isUnixSocketFile(path) else { continue }
            unlink(path)
        }
        reclaimStaleWarpHelperOccupations(in: directory)
    }
}

/// **How long after the launch line is written a helper may still take its address.**
///
/// The previous number was derived from Tab Config lifetime + `open` timeout + how long the pane
/// takes to appear, and **that is not a bound** (round 23 review): "the instruction after `listen`"
/// is not a time, and a suspended process can be anywhere. The helper's own caps do not close it
/// either — the 180-second idle cap and the 900-second lifetime cap both start once it is *serving*,
/// which is after the claim, so a helper suspended before the claim had no cap at all.
///
/// So the helper is handed this at birth and refuses to claim past it. That is not a check on app
/// state — the shape round 17 ruled out — but the helper bounding itself against a constant it was
/// given, which needs nothing to be reachable and nothing to still be true.
///
/// Two minutes: `open` alone is allowed fifteen seconds, the pane follows 0.5∼0.7s after it returns
/// (measured), and the rest is slack for a machine under load. A helper that has not claimed in two
/// minutes has lost its pane or its scheduler, and delivery has failed either way.
public let warpHelperClaimWindow: TimeInterval = 120

/// When the sweep may take what a take-back left, and the pin it linked from.
///
/// It is **the number the helper enforces**, plus slack — not an optimistic derivation of its own.
/// Once the window has passed no helper will claim, so nothing is being protected any more.
let warpHelperOccupationLifetime: TimeInterval = warpHelperClaimWindow + 60

/// Removes what taking an address back leaves: the occupied name and the pin it was linked from.
///
/// Both are **regular files**, which is why the socket sweep above passes them by and why they
/// needed a rule of their own. A live helper's address is a socket and is never in range here.
func reclaimStaleWarpHelperOccupations(
    in directory: String, olderThan lifetime: TimeInterval = warpHelperOccupationLifetime
) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    for name in names where warpHelperSocketFileIsOurs(name: name) || warpHelperPinFileIsOurs(name: name) {
        let path = (directory as NSString).appendingPathComponent(name)
        guard let modified = fileModificationDate(path),
              Date().timeIntervalSince(modified) > lifetime
        else { continue }
        removeWarpHelperFileIfOurs(path: path)
    }
}

/// Deletes one only when its **contents** say it is ours.
///
/// The name is not enough and deliberately so: the socket sweeps are narrow because anyone can drop
/// a regular file under one of our names, and a sweep that took regular files by name would hand
/// that protection back. The verdict is reached through an fd — `O_NOFOLLOW` excludes links from the
/// outset and the `fstat` and the read are on that same descriptor, so "what was checked" and "what
/// was read" are one file — and then one more `lstat` before the `unlink` narrows the window that
/// remains, exactly as `removeWarpTabConfigIfOurs` does for a Tab Config.
func removeWarpHelperFileIfOurs(path: String) {
    let fd = open(path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { return }
    defer { close(fd) }

    // **The whole file, not a prefix of it.** Reading the marker's length and comparing says the file
    // *begins* our way, which a user file that starts with the same line also does — and this deletes
    // what it matches (round 23 review). The size is the other half of "this is our file".
    let expected = Array(warpHelperPinMarker.utf8)
    var opened = stat()
    guard fstat(fd, &opened) == 0,
          (opened.st_mode & S_IFMT) == S_IFREG,
          opened.st_size == off_t(expected.count)
    else { return }

    var head = [UInt8](repeating: 0, count: expected.count)
    let count = read(fd, &head, head.count)
    guard count == expected.count, head == expected else { return }

    var current = stat()
    guard lstat(path, &current) == 0,
          current.st_ino == opened.st_ino, current.st_dev == opened.st_dev
    else { return }
    unlink(path)
}

/// A type check that does not follow symbolic links — following one deletes whatever file the link points at.
private func isUnixSocketFile(_ path: String) -> Bool {
    var info = stat()
    guard lstat(path, &info) == 0 else { return false }
    return (info.st_mode & S_IFMT) == S_IFSOCK
}

/// Deletes only the Tab Configs we created. The scheduled deletion fires 20 seconds later, and in that time the user may have put their own file or link at the same path.
///
/// The verdict is reached **through an fd**: opening with `O_NOFOLLOW` excludes links from the outset, and doing both the `fstat` and the content read on that same fd guarantees "what was checked" and "what was read" are the same file. Looking twice by path leaves room for a swap in between.
///
/// The remaining window: macOS has no `funlinkat`, so the final `unlink` alone has to go by path. One more `lstat` immediately before it re-confirms the inode and narrows the window to tens of microseconds, but it cannot be closed entirely — the worst outcome is "one file slipped exactly into that window gets deleted", and doing that requires knowing our random name in advance, which is only possible from the same uid.
func removeWarpTabConfigIfOurs(path: String) {
    guard warpTabConfigFileIsOurs(name: (path as NSString).lastPathComponent) else { return }
    let fd = open(path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { return }
    defer { close(fd) }

    var opened = stat()
    guard fstat(fd, &opened) == 0, (opened.st_mode & S_IFMT) == S_IFREG else { return }

    var head = [UInt8](repeating: 0, count: 512)
    let count = read(fd, &head, head.count)
    guard count > 0,
          warpTabConfigIsOurs(contents: String(decoding: head[0..<count], as: UTF8.self))
    else { return }

    var current = stat()
    guard lstat(path, &current) == 0,
          current.st_ino == opened.st_ino, current.st_dev == opened.st_dev
    else { return }
    unlink(path)
}

/// When the app dies before deleting its own Tab Config, the file survives and piles up in Warp's `+` menu.
/// The age is checked in order not to delete another request's file that is opening right now, and the contents are checked in order not to delete a user file whose name collides. Both are reasons for the checks, not promises about their outcome — the residual window is in `removeWarpTabConfigIfOurs`.
func reclaimStaleWarpTabConfigs(
    in directory: String = warpTabConfigDirectory(), olderThan age: TimeInterval = 300
) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    for name in names where warpTabConfigFileIsOurs(name: name) {
        let path = (directory as NSString).appendingPathComponent(name)
        guard let modified = fileModificationDate(path),
              Date().timeIntervalSince(modified) > age
        else { continue }
        removeWarpTabConfigIfOurs(path: path)
    }
}

private func fileModificationDate(_ path: String) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
}

// MARK: - The helper socket client

/// Sends one request and receives one response line. nil when the connection, the send, or the parse fails — the caller must treat that as "this call failed" and nothing more (it does not mean the session is over).
///
/// The wait is derived from the helper's work budget (`warpHelperRequestTimeout`) — if the app gives up first and retries while the helper keeps injecting, those bytes mix with the retry's.
func warpHelperRequest(
    _ request: WarpHelperRequest, socket path: String,
    timeout: TimeInterval = warpHelperRequestTimeout
) -> WarpHelperResponse? {
    guard let fd = connectToUnixSocket(path: path) else { return nil }
    defer { close(fd) }

    // Keeps the delivery thread from hanging forever when the helper does not answer
    var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    guard writeAll(fd: fd, data: Data((encodeWarpHelperRequest(request) + "\n").utf8)) else { return nil }

    var buffer = LineBuffer()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        if let line = buffer.nextLine() { return parseWarpHelperResponse(line) }
        let n = read(fd, &chunk, chunk.count)
        if n > 0 {
            buffer.append(Data(chunk[0..<n]))
            if buffer.isOverflowed { return nil }
        } else if n < 0 && errno == EINTR {
            continue
        } else {
            return nil
        }
    }
}
