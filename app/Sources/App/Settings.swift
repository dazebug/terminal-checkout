import Core
import Foundation

/// 앱이 단일 소스로 관리하는 설정. 터미널 선택은 확장이 아니라 여기서 결정된다.
enum Settings {
    static var terminal: Terminal {
        get {
            if let value = UserDefaults.standard.string(forKey: "terminal") {
                return Terminal(storedValue: value)
            }
            // 기본값: 설치된 터미널 자동 감지. 순서는 지원이 오래돼 실사용으로 다져진
            // 순이다 — Warp는 pane을 지목할 정식 API가 없어 헬퍼 프로세스를 끼우므로 마지막
            if PermissionChecker.isITermInstalled { return .iterm }
            if PermissionChecker.isWezTermInstalled { return .wezterm }
            if PermissionChecker.isWarpInstalled { return .warp }
            return .iterm
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "terminal") }
    }

    /// The top-level folder repositories are cloned into — where a command moves when `z` fails.
    /// This only **stores the string**; validation, normalization, and fragment assembly all live
    /// in Core (`normalizedBaseDirectory`, `repoEntryCommand`). The extension neither knows nor
    /// sends this value: paths differ per machine while extension settings ride storage.sync
    /// across an account.
    ///
    /// A stored value that isn't a string (a hand-edited plist, some future build writing another
    /// type) must not read as "not configured" — that is exactly the silent fold decision 4 rules
    /// out. It is handed on as text instead, so `normalizedBaseDirectory` rejects it and the button
    /// fails carrying the reason. `string(forKey:)` cannot express that: it returns nil for both
    /// "absent" and "present but another type".
    static var baseDirectory: String {
        get {
            guard let stored = UserDefaults.standard.object(forKey: "baseDirectory") else { return "" }
            return stored as? String ?? String(describing: stored)
        }
        set { UserDefaults.standard.set(newValue, forKey: "baseDirectory") }
    }

    /// The language the user picked, or `auto`. Stored as text and handed to `resolveLocale` as the
    /// **object** it came back as — a value that is not a string must not read as "follow the
    /// system", which is the same fold `baseDirectory` refuses just above.
    ///
    /// Setting it is what makes this process a writer (D49): the picker lives in the setup window,
    /// so only the GUI reaches here. It publishes immediately, so the revision moves in the same
    /// process that took the click rather than on the next launch.
    static var language: String {
        get { (UserDefaults.standard.object(forKey: languagePreferenceKey) as? String) ?? automaticLocalePreference }
        set {
            UserDefaults.standard.set(newValue, forKey: languagePreferenceKey)
            LocaleState.publish(
                resolved: AppLocalization.resolvedTag(), role: .interactive
            )
            NotificationCenter.default.post(name: .terminalCheckoutLanguageChanged, object: nil)
        }
    }

    /// 소켓으로 마지막 요청이 도착한 시각 — "확장이 Chrome에 로드되어 실제로 연결됐다"는 유일한 증거.
    /// (폴더 준비 여부만으로는 Chrome 로드 완료를 알 수 없다)
    static var lastRequestAt: Date? {
        get { UserDefaults.standard.object(forKey: "lastRequestAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastRequestAt") }
    }

    static func recordRequestEvidence() {
        lastRequestAt = Date()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .terminalCheckoutRequestHandled, object: nil)
        }
    }

    /// 명령이 부르는 도구(z/gh/claude)의 마지막 확인 결과. 확인은 로그인 셸을 띄우느라
    /// 시간이 걸리므로, 창이 열리자마자 보여줄 직전 값을 남겨 둔다. 확인 전이면 nil.
    static var toolAvailability: [String: Bool]? {
        get { UserDefaults.standard.dictionary(forKey: "toolAvailability") as? [String: Bool] }
        set { UserDefaults.standard.set(newValue, forKey: "toolAvailability") }
    }

    /// 같은 확인의 다른 사실: 그 이름이 **실행 파일**로 풀리는가. 병합 경로는 `command claude`로
    /// 부르므로 함수·별칭뿐인 설치에서는 병합이 성립하지 않는다.
    static var toolExecutables: [String: Bool]? {
        get { UserDefaults.standard.dictionary(forKey: "toolExecutables") as? [String: Bool] }
        set { UserDefaults.standard.set(newValue, forKey: "toolExecutables") }
    }

    /// 확인 **전**에는 참으로 본다 — 앱이 방금 떠서 아직 로그인 셸을 못 물어본 순간에 병합을
    /// 꺼 버리면, 흔한 설치(실행 파일)에서 프리셋이 느려지거나 Warp에서는 권한 없이 거절까지
    /// 간다. 반대 방향의 오판은 pane에 command not found 한 줄로 드러나고 다음 확인에서 고쳐진다
    static var claudeIsExecutable: Bool { toolExecutables?["claude"] ?? true }

    /// 앱 실행 때마다 다시 확인한다 — 사용자가 그 사이 도구를 설치했을 수 있다.
    /// 확인에 실패하면(셸이 응답하지 않음) 직전 결과를 그대로 둔다.
    static func refreshToolAvailability() {
        DispatchQueue.global(qos: .utility).async {
            guard let result = checkTools() else {
                checkoutLog("도구 확인 실패 — 로그인 셸이 응답하지 않음")
                return
            }
            toolAvailability = result.available
            toolExecutables = result.executable
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .terminalCheckoutToolsChecked, object: nil)
            }
        }
    }
}

extension Notification.Name {
    /// 소켓 요청 처리 시 발행 — 설정 창이 열려 있으면 상태를 실시간 갱신한다
    static let terminalCheckoutRequestHandled = Notification.Name("TerminalCheckoutRequestHandled")
    /// 도구 확인이 끝났을 때 발행 — 확인은 백그라운드라 창이 먼저 열려 있을 수 있다
    static let terminalCheckoutToolsChecked = Notification.Name("TerminalCheckoutToolsChecked")
    /// 언어 선택이 바뀐 뒤 발행 — 우리 문자열은 재시작 없이 즉시 다시 그린다(D14)
    static let terminalCheckoutLanguageChanged = Notification.Name("TerminalCheckoutLanguageChanged")
}

/// Whether restarting right now would cut something off.
///
/// **A seam, not an answer.** The condition itself is item 13's: a language restart must not run
/// while claude input is still being delivered, because that delivery is asynchronous and the Warp
/// injection helper's only defence is its lifetime — a restart that orphans it breaks the trust
/// boundary `CLAUDE.md` sets out. Until that lands this says yes, which is today's behaviour
/// unchanged; what the seam buys is that item 13 has exactly one place to fill and the picker
/// already asks.
enum LocaleRestartGate {
    /// Replaced by item 13. Left as a stored closure rather than a computed condition so the
    /// question and the answer stay separable — the picker calls it without knowing what it checks.
    static var isSafeNow: () -> Bool = { true }
}

// MARK: - The published locale snapshot

/// Which process is asking. **Only one may write** (D49): the GUI is the process that owns the
/// picker, so it is the only one with a reason to move the revision. `--headless-server` shares the
/// bundle id and therefore `UserDefaults.standard` with it, and two read-modify-writes against the
/// same key can publish **different locales under the same epoch** — after which the extension,
/// whose rule is "same install, accept only a strictly greater epoch", drops the newer of the two.
/// Making the second writer impossible removes the case rather than locking around it.
enum LocaleWriterRole {
    /// The GUI: has a picker, may mint an identity and advance the revision.
    case interactive
    /// The headless server: publishes what the GUI last wrote, and writes nothing.
    case headless
}

/// What goes out to the extension: which locale, and how the extension is to order it.
struct LocalePublication: Equatable {
    /// Identity of the app's data. A different one means "this is a different install" and the
    /// extension accepts unconditionally — which is what makes a reset distinguishable from a stale
    /// message, something a single integer cannot express (D32).
    let installId: String
    let snapshot: LocaleSnapshot
}

/// Reading, minting and advancing the published snapshot.
///
/// The verdict itself is pure and lives in Core (`localeSnapshotToPublish`). What lives here is
/// everything that function deliberately does not know: where the snapshot is kept, what a
/// half-written one means, and who may write. Those are invariants of the caller and of storage,
/// not of the function, which is why they are proved here instead of by widening it (D67).
enum LocaleState {
    static let installIdKey = "localeInstallId"
    static let epochKey = "localeEpoch"
    static let publishedTagKey = "localePublishedTag"

    /// A stored snapshot counts only when **all three** parts are there and readable. A partial one
    /// is not "epoch 0 of this install": republishing 0 under an identity the extension already
    /// holds would lose to its cached higher epoch, and the app would look stuck in the old
    /// language forever. It counts as no identity at all, and a new one is minted (D51).
    ///
    /// `Int.max` is malformed for the same reason absence is — the next revision cannot be
    /// expressed, so staying under this identity would mean publishing changes the extension is
    /// required to ignore.
    private static func stored(_ defaults: UserDefaults) -> LocalePublication? {
        guard let installId = defaults.object(forKey: installIdKey) as? String, !installId.isEmpty,
              let epoch = defaults.object(forKey: epochKey) as? Int, epoch >= 0, epoch < Int.max,
              let tag = defaults.object(forKey: publishedTagKey) as? String,
              supportedLocales.contains(tag)
        else { return nil }
        return LocalePublication(
            installId: installId, snapshot: LocaleSnapshot(tag: tag, epoch: epoch)
        )
    }

    /// What this process should publish for `resolved`, and — for the one writer — the persistence
    /// that makes it true for the next one.
    ///
    /// The headless server never invents a revision. With a stored snapshot it repeats it verbatim,
    /// even when this launch resolves to a different locale: a system-language change seen only by
    /// a headless process arrives on the next GUI launch, which is the promise `auto` already
    /// makes. With nothing stored it publishes **nothing** (nil) — a response carrying no locale
    /// metadata, which the extension treats as no input rather than as a reason to change (D51).
    @discardableResult
    static func publish(
        resolved: String, defaults: UserDefaults = .standard, role: LocaleWriterRole
    ) -> LocalePublication? {
        guard let stored = stored(defaults) else {
            guard role == .interactive else { return nil }
            let minted = LocalePublication(
                installId: UUID().uuidString, snapshot: LocaleSnapshot(tag: resolved, epoch: 0)
            )
            write(minted, to: defaults)
            return minted
        }
        guard stored.snapshot.tag != resolved else { return stored }
        guard role == .interactive else { return stored }
        let advanced = LocalePublication(
            installId: stored.installId,
            snapshot: localeSnapshotToPublish(resolved: resolved, lastPublished: stored.snapshot)
        )
        write(advanced, to: defaults)
        return advanced
    }

    private static func write(_ publication: LocalePublication, to defaults: UserDefaults) {
        defaults.set(publication.installId, forKey: installIdKey)
        defaults.set(publication.snapshot.epoch, forKey: epochKey)
        defaults.set(publication.snapshot.tag, forKey: publishedTagKey)
    }
}
