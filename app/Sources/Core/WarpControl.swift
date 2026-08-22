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
/// greps for it and `warpTabConfigIsOurs` matches it by prefix, and those three copies have to stay
/// byte-identical — a divergence means files nobody deletes. Anything a human should read goes on
/// the line **below** it (`warpTabConfigTOML`), where translating it is harmless.
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
    contents.hasPrefix(warpTabConfigHeader) || contents.hasPrefix(warpTabConfigLegacyHeader)
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

/// Both arguments are absolute paths, single-quoted — nothing in the user's shell (PATH,
/// functions, aliases) can change what this line runs.
public func warpHelperCommand(executable: String, socketPath: String) -> String {
    "\(shellSingleQuoted(executable)) \(shellSingleQuoted(socketPath))"
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
public func warpHelperSocketFileIsOurs(name: String) -> Bool {
    guard name.hasPrefix(warpHelperSocketPrefix), name.hasSuffix(".sock") else { return false }
    return isOurRequestToken(name.dropFirst(warpHelperSocketPrefix.count).dropLast(".sock".count))
}

public let warpHelperSocketPrefix = "tcw-"

/// The first candidate directory whose path fits in sun_path's 104 bytes. nil when none of them fits.
public func warpHelperSocketPath(token: String, directories: [String]) -> String? {
    for directory in directories {
        let path = (directory as NSString).appendingPathComponent("\(warpHelperSocketPrefix)\(token).sock")
        if makeUnixSockaddr(path) != nil { return path }
    }
    return nil
}

/// A temporary directory is used because its path is short, which leaves headroom against sun_path's 104-byte limit.
/// The OS is not relied on to clean up what is left behind — when the helper ends on SIGKILL its `unlink` never runs, so the next run reclaims dead sockets itself (`reclaimDeadWarpHelperSockets`).
public func warpHelperSocketPath(token: String) -> String? {
    warpHelperSocketPath(token: token, directories: [NSTemporaryDirectory(), "/tmp"])
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
    }
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
