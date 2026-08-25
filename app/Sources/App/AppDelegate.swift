import AppKit
import Core

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: HostServer?
    private var setupWindow: SetupWindowController?
    private var languageObserver: NSObjectProtocol?

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
        // until something rebuilds them. Registered here rather than inside
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
    /// `depart()` shuts the delivery gate before dismissing helpers. Termination is not refusable, so
    /// a request already accepted on the socket queue must not launch a helper after cleanup has run;
    /// the gate and cleanup preserve that ordering and hand back the proof the farewell asks for.
    func applicationWillTerminate(_ notification: Notification) {
        let departure = ClaudeDelivery.depart()
        ClaudeDelivery.endEveryHelper(departure)
        server?.stop()
    }

    /// Starts the socket server after the app has adopted its stored language. Binding is the
    /// process's ownership check; request handling is the only work the socket path performs.
    private func startServer() {
        let server = HostServer(socketPath: defaultSocketPath())
        do {
            try server.start()
            self.server = server
        } catch {
            checkoutLog("socket server failed to start — \(errorMessage(error))")
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
