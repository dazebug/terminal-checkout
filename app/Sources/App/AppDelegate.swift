import AppKit
import Core

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: HostServer?
    private var setupWindow: SetupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startServer()
        Installer.autoSetup()
        Settings.refreshToolAvailability()
        setupMainMenu()
        // relay가 백그라운드로 띄운 경우(--background)에는 창을 열지 않는다
        if !CommandLine.arguments.contains("--background") {
            showSetupWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetupWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func startServer() {
        let server = HostServer(socketPath: defaultSocketPath())
        do {
            try server.start()
            self.server = server
        } catch {
            checkoutLog("소켓 서버 시작 실패 — \(errorMessage(error))")
        }
    }

    /// 프로그램 방식 앱은 메인 메뉴가 없으면 ⌘C/⌘V/⌘W 등이 동작하지 않는다
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "\(appDisplayName) 종료",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "윈도우")
        windowMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = main
    }

    /// 앱은 어디에도 상시 노출되지 않는다 (메뉴 막대 없음, Dock은 창이 열린 동안만).
    /// 설정이 필요하면 Spotlight 등으로 앱을 다시 실행 → reopen 이벤트로 이 창이 열린다.
    private func showSetupWindow() {
        if setupWindow == nil {
            let controller = SetupWindowController()
            // 창이 닫히면 Dock/⌘Tab에서 다시 숨긴다 (보이지 않는 백그라운드로 복귀)
            controller.onClose = { NSApp.setActivationPolicy(.accessory) }
            setupWindow = controller
        }
        // 창이 열려 있는 동안은 Dock/⌘Tab에 나타나도록 일반 앱으로 전환
        NSApp.setActivationPolicy(.regular)
        setupWindow?.showWindow(nil)
        setupWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
