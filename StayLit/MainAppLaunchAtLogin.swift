import StayLitCore
import ServiceManagement

/// The app itself is the login item: there is no helper app to embed.
nonisolated struct MainAppLaunchAtLogin: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        // A main app never registered reads as `.notFound`, not `.notRegistered`.
        // Disabling the switch then would block the first registration; `register()` reports real failures.
        case .notRegistered, .notFound: .disabled
        case .requiresApproval: .requiresApproval
        @unknown default: .unavailable
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
