import AppKit
import Core

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The language this launch resolved to, decided in `main.swift` before AppKit was touched and
    /// carried here so that publishing it does not mean resolving it a second time.
    private let launchLocale: SupportedLocale
    private var server: HostServer?
    private var setupWindow: SetupWindowController?
    private var languageObserver: NSObjectProtocol?

    init(launchLocale: SupportedLocale) {
        self.launchLocale = launchLocale
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Takes the user somewhere that explains a rejection. The extension shows a failure as a
        // single ❌ and the reason string only reaches the console (issue #29), so this window is
        // the only channel the app has. Rejections come off the socket queue, hence the hop to
        // main. The headless server (`--headless-server`) never builds this delegate, so the hook
        // stays nil there — which is why e2e does not open a window
        ClaudeInputGuidance.present = { [weak self] _ in
            DispatchQueue.main.async { self?.showSetupWindow() }
        }
        startServer()
        Installer.autoSetup()
        Settings.refreshToolAvailability()
        setupMainMenu()
        // The menu bar is built once, so its titles keep whatever language they were built in
        // until something rebuilds them (item 9). Registered here rather than inside
        // `setupMainMenu` so that building and re-building stay one call each
        languageObserver = NotificationCenter.default.addObserver(
            forName: .terminalCheckoutLanguageChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.setupMainMenu() }
        // Launched in the background by the relay (`--background`): no window
        if !CommandLine.arguments.contains("--background") {
            showSetupWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetupWindow()
        return true
    }

    /// **The helpers go before the app does.**
    ///
    /// A Warp injection helper is a separate process living in the user's pane, and its only defence
    /// is that it dies when the delivery ends (`CLAUDE.md`). If this app goes away mid-delivery the
    /// `defer` that would have said goodbye never runs, and the helper is left listening on a socket
    /// any process with the same uid can reach. So the farewell is sent from here too, first —
    /// stopping our own socket server is ours to lose, the helper is the user's machine.
    ///
    /// **Whether it completes inside the termination budget is not something this repository can
    /// establish**: macOS allows a few seconds, each farewell is one socket round trip, and there is
    /// no way here to observe the case where that is not enough. The claim is that the attempt is
    /// made and ordered first, not that it always finishes.
    /// **The gate closes before the farewells go out**, and that order is the point.
    ///
    /// Round 14 gave the language restart an admission gate and left this path calling cleanup
    /// without it: a request already accepted on the socket queue could reach `runInTerminal` and
    /// launch a Warp helper *after* `endEveryHelper` had said goodbye to everyone it could see, and
    /// that helper would outlive the app with nobody to dismiss it (round 15 review). Termination is
    /// not refusable, so `depart()` shuts the gate whatever is in flight — and hands back the proof
    /// the farewell asks for, which is why the two lines below cannot be written the other way round.
    func applicationWillTerminate(_ notification: Notification) {
        let departure = ClaudeDelivery.depart()
        ClaudeDelivery.endEveryHelper(departure)
        server?.stop()
    }

    /// **This is where publication eligibility is decided**, and the only place it is.
    ///
    /// `start()` throws `alreadyRunning` when another instance answers on the path, and that is the
    /// only singleton test this app has — `NSLock` is process-local and cannot see a second process
    /// at all (round 14 review). Two GUI instances are not hypothetical: the language restart
    /// relaunches with `open -n`, which is exactly how you get one. Publishing from a process that
    /// does not own the socket produces two different locales under the same install id and epoch,
    /// which the extension's ordering rule cannot separate — it keeps whichever it saw first.
    ///
    /// The publication moved here from `main.swift` in round 14; what stayed there is the
    /// *resolution*, so the answer published is still the one this launch decided on before AppKit
    /// was touched. **What round 14 got wrong was the scope of the claim**: this bound the launch
    /// writer and the sentence here said "only the instance that owns the socket publishes", while
    /// the picker went on publishing from anywhere (round 15 review). Round 15 gave both writers one
    /// type to ask and left the launch writer publishing whatever it was handed, so **this ordering
    /// was still the only thing enforcing it** (round 16 review).
    ///
    /// Now the bind hands back the right and publishing takes one, so the line below could not be
    /// moved above `start()` even by accident: there would be nothing to pass. What is left here is
    /// no longer a rule — it is the plumbing of a value.
    private func startServer() {
        let server = HostServer(socketPath: defaultSocketPath())
        do {
            let right = try server.start()
            self.server = server
            Settings.publishLocaleAtLaunch(resolved: launchLocale, right: right)
        } catch {
            checkoutLog(
                "socket server failed to start, so this instance publishes no locale — \(errorMessage(error))"
            )
        }
    }

    /// An app built in code has no main menu unless it makes one, and without it ⌘C/⌘V/⌘W do nothing.
    ///
    /// Every title is read at the moment the menu is built, so a language change rebuilds it (the
    /// observer above) rather than translating anything in place.
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: localized("app.menu.quit", appDisplayName),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: localized("app.menu.edit"))
        editMenu.addItem(withTitle: localized("app.menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: localized("app.menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: localized("app.menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: localized("app.menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: localized("app.menu.window"))
        windowMenu.addItem(withTitle: localized("app.menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = main
    }

    /// The app is nowhere on screen while it is idle — no menu bar item, and a Dock icon only while
    /// this window is open. Launching it again (from Spotlight, say) arrives as a reopen event,
    /// which is what brings the window back.
    private func showSetupWindow() {
        if setupWindow == nil {
            let controller = SetupWindowController()
            // Closing the window hides it from the Dock and ⌘Tab again — back to the invisible background
            controller.onClose = { NSApp.setActivationPolicy(.accessory) }
            setupWindow = controller
        }
        // A regular app while the window is up, so it appears in the Dock and ⌘Tab
        NSApp.setActivationPolicy(.regular)
        setupWindow?.showWindow(nil)
        setupWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
