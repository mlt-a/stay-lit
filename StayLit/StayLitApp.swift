import SwiftUI

@main
struct StayLitApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusView(
                model: delegate.model,
                requestNotificationPermission: delegate.requestNotificationPermission
            )
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}
