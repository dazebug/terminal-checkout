/// The single identifier for a supported terminal. The rawValue *is* the value stored in `UserDefaults` — `iterm` is an identifier that denotes iTerm2 regardless of the product's name, so it does not change.
/// Adding a case makes every `default`-less switch a compile error, which is how the branches that need touching reveal themselves — for the branches that live outside a switch (visibility conditions and the like) and for the hands-on checks, docs/new-terminal-checklist.md is the source of truth.
public enum Terminal: String, CaseIterable {
    case iterm
    case wezterm
    case warp
    case cmux
    case cmuxNightly = "cmux-nightly"

    /// The single place a stored value is parsed. An unknown value (an identifier left by another version, a hand-edited plist) falls back to iTerm2.
    /// Scattering that fallback across the consumers is how they drift apart — execution going to iTerm2 while the setup window hides the iTerm2 permission section — so it lives here and nowhere else.
    public init(storedValue: String) {
        self = Terminal(rawValue: storedValue) ?? .iterm
    }

    /// The two cmux channels share every code path; this is the one mapping from the stored
    /// identifier to the channel those shared paths are parameterized by.
    public var cmuxChannel: CmuxChannel? {
        switch self {
        case .cmux: return .stable
        case .cmuxNightly: return .nightly
        case .iterm, .wezterm, .warp: return nil
        }
    }
}
