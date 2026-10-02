import AppKit
import ServiceManagement

enum LoginItemStatus: Equatable {
    case enabled
    case disabled
    /// Registered, but the user has to allow it in System Settings → General → Login Items.
    case requiresApproval
}

protocol LoginItemManaging {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Opens this app at login. The Slack shortcut only works while the app runs, and nothing else
/// starts the app after a login until a Chrome button or the user does.
struct MainAppLoginItem: LoginItemManaging {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        // `.notFound` is what an app that never registered can report; registering is the way out
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Whether AppKit is handling the open event loginwindow sends a login item. Read while
/// `applicationDidFinishLaunching` runs, when that event is the current one.
func launchedAsLoginItem() -> Bool {
    guard let event = NSAppleEventManager.shared().currentAppleEvent,
          event.eventID == kAEOpenApplication else { return false }
    return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
}
