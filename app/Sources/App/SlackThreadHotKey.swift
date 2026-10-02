import AppKit
import Carbon.HIToolbox
import Core

struct HotKeyRegistrationError: Error, Equatable {
    let status: Int32
}

enum SlackThreadHotKeyError: Error {
    case serverUnavailable
}

/// The one system-wide registration this app holds. A second `register` replaces the first.
protocol HotKeyRegistering: AnyObject {
    func register(_ combination: HotKeyCombination, onPress: @escaping () -> Void) throws
    func unregister()
}

/// Registers through Carbon's `RegisterEventHotKey`, which the window server matches before any app
/// sees the key — so the shortcut fires whichever app is in front. A shortcut assigned in the
/// Shortcuts app does not: it is a Services key equivalent that only apps handling Services act on,
/// and Slack does not (measured; `docs/context/slack-thread-shortcut.md`).
final class CarbonHotKeyRegistrar: HotKeyRegistering {
    typealias RegisterHotKey = (
        _ keyCode: UInt32, _ modifiers: UInt32, _ identifier: EventHotKeyID, _ options: OptionBits,
        _ reference: inout EventHotKeyRef?
    ) -> OSStatus

    private static let signature: OSType = 0x5443_534C // 'TCSL'
    private let registerHotKey: RegisterHotKey
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPress: (() -> Void)?

    init(registerHotKey: @escaping RegisterHotKey = { keyCode, modifiers, identifier, options, reference in
        RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), options, &reference)
    }) {
        self.registerHotKey = registerHotKey
    }

    /// The handler holds an unretained pointer to this object, so it goes when the object does.
    deinit {
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func register(_ combination: HotKeyCombination, onPress: @escaping () -> Void) throws {
        unregister()
        try installHandlerIfNeeded()
        // Exclusive, or a combination another app already holds exclusively registers "successfully"
        // and never fires (measured) — the refusal is what lets the window say so.
        var reference: EventHotKeyRef?
        let status = registerHotKey(
            combination.keyCode, combination.modifiers.rawValue,
            EventHotKeyID(signature: Self.signature, id: 1), OptionBits(kEventHotKeyExclusive), &reference
        )
        guard status == noErr, let reference else {
            throw HotKeyRegistrationError(status: status)
        }
        hotKeyRef = reference
        self.onPress = onPress
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        onPress = nil
    }

    /// Installed once and kept: the handler only forwards to whatever `onPress` currently is.
    private func installHandlerIfNeeded() throws {
        guard handlerRef == nil else { return }
        var pressed = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let read = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
                )
                guard read == noErr, identifier.signature == CarbonHotKeyRegistrar.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue().onPress?()
                return noErr
            },
            1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard status == noErr else { throw HotKeyRegistrationError(status: status) }
    }
}

enum SlackThreadHotKeyState: Equatable {
    case off
    case active(HotKeyCombination)
    case failed(HotKeyCombination, status: Int32)
}

/// What the setup window may ask of the app's shortcut.
protocol SlackThreadHotKeyManaging: AnyObject {
    var combination: HotKeyCombination? { get }
    var state: SlackThreadHotKeyState { get }
    var onStateChange: ((SlackThreadHotKeyState) -> Void)? { get set }
    func apply(_ combination: HotKeyCombination?)
    func suspend()
    func resume()
}

/// Owns the Slack thread shortcut: keeps the registration matching the stored choice and turns a
/// press into a request carrying whatever text is on the clipboard at that moment.
final class SlackThreadHotKeyController: SlackThreadHotKeyManaging {
    typealias Completion = (Result<Void, Error>) -> Void

    private let registrar: HotKeyRegistering
    private let readClipboard: () -> String?
    private let execute: (String?, @escaping Completion) -> Void
    private let presentFailure: (Error) -> Void
    private let clearFailure: () -> Void
    private let log: (String) -> Void
    private var suspended = false

    private(set) var combination: HotKeyCombination?
    private(set) var state: SlackThreadHotKeyState = .off {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((SlackThreadHotKeyState) -> Void)?

    init(
        registrar: HotKeyRegistering,
        readClipboard: @escaping () -> String?,
        execute: @escaping (String?, @escaping Completion) -> Void,
        presentFailure: @escaping (Error) -> Void,
        clearFailure: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.registrar = registrar
        self.readClipboard = readClipboard
        self.execute = execute
        self.presentFailure = presentFailure
        self.clearFailure = clearFailure
        self.log = log
    }

    func apply(_ combination: HotKeyCombination?) {
        self.combination = combination
        guard !suspended else { return }
        register()
    }

    /// While the setup window records a new shortcut, the old one must not fire on the keys typed.
    func suspend() {
        suspended = true
        registrar.unregister()
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        register()
    }

    private func register() {
        guard let combination else {
            registrar.unregister()
            state = .off
            return
        }
        do {
            try registrar.register(combination) { [weak self] in self?.pressed() }
            state = .active(combination)
        } catch let error as HotKeyRegistrationError {
            log("Slack thread shortcut was not registered (status \(error.status))")
            state = .failed(combination, status: error.status)
        } catch {
            log("Slack thread shortcut was not registered — \(errorMessage(error))")
            state = .failed(combination, status: 0)
        }
    }

    private func pressed() {
        execute(readClipboard()) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.clearFailure()
            case .failure(let error):
                self.log("Slack thread request failed — \(errorMessage(error))")
                self.presentFailure(error)
            }
        }
    }
}

/// The four modifiers a shortcut can carry; Caps Lock, Fn and the keypad flag are not part of one.
func hotKeyModifiers(from flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
    var modifiers: HotKeyModifiers = []
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.control) { modifiers.insert(.control) }
    return modifiers
}

private let fixedKeyLabels: [Int: String] = [
    kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
    kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
    kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
]

/// Names a key the way its keycap reads. Character keys go through the current ASCII-capable layout,
/// so a Korean or Japanese input source still shows `C` for the C key rather than a composed glyph.
func hotKeyKeyLabel(_ keyCode: UInt32) -> String {
    if let fixed = fixedKeyLabels[Int(keyCode)] { return fixed }
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
          let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return "#\(keyCode)"
    }
    let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
    var deadKeyState: UInt32 = 0
    var characters = [UniChar](repeating: 0, count: 4)
    var length = 0
    let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
        guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
            return OSStatus(paramErr)
        }
        return UCKeyTranslate(
            layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
        )
    }
    guard status == noErr, length > 0 else { return "#\(keyCode)" }
    let label = String(utf16CodeUnits: characters, count: length).uppercased()
    return label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "#\(keyCode)" : label
}
