import AppKit
import ServiceManagement

enum LoginItemStatus: Equatable {
    case enabled
    case disabled
    /// Registered, but waiting for the user to allow it under Login Items in System Settings.
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
        // `.notFound` is shown as not registered: registering is the way forward from either
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

/// True when the open event AppKit is handling carries `keyAELaunchedAsLogInItem`; call it from
/// `applicationDidFinishLaunching`. Not yet observed for an `SMAppService` login launch, which needs
/// a logout — if the flag is absent, the setup window opens at login and can simply be closed.
func launchedAsLoginItem() -> Bool {
    guard let event = NSAppleEventManager.shared().currentAppleEvent,
          event.eventID == kAEOpenApplication else { return false }
    return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
}
