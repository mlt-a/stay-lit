import StayLitCore
import SwiftUI

/// The window under the menu bar icon: the lid first, then when the Mac sleeps again, then
/// the general settings.
struct StatusView: View {
    let model: AppModel
    /// Asks the system for the right to notify, once. Previews and the demo leave it empty.
    var requestNotificationPermission: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LidSection(model: model)
            Divider()
            SleepConditionsSection(model: model)
            Divider()
            GeneralSection(model: model)
        }
        .padding(16)
        .frame(width: 320)
        // The window can stay mounted between openings: read the state each time it is shown.
        .task {
            if guardNeedsNotifications { requestNotificationPermission() }
            await model.refresh()
        }
    }

    /// The guards' only message outside the window is a notification:
    /// ask once the window shows, not only when a guard fires with nobody at the screen.
    private var guardNeedsNotifications: Bool {
        (model.isBatteryGuardEnabled && model.hasBattery) || model.isTemperatureGuardEnabled
            || model.isClaudeGuardEnabled
    }
}
