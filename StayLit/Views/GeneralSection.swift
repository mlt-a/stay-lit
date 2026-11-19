import StayLitCore
import SwiftUI

/// Launch at login, the password-free rule, who made the app, and Quit.
struct GeneralSection: View {
    let model: AppModel

    /// Not translated: a name.
    private static let author = "mlt-a"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            launchAtLoginRow
            if model.authorization == .authorized {
                SettingRow(title: Text("Password-free rule")) {
                    Text("Two pmset commands, nothing else.")
                        .captionStyle()
                } control: {
                    Button("Remove…") {
                        Task { await model.removeAuthorization() }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Remove the rule")
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("removeAuthorizationButton")
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Stay Lit \(Self.version)")
                    Text("Made by \(Self.author)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .accessibilityIdentifier("quitButton")
            }
            .padding(.top, 4)
        }
    }

    private var launchAtLoginRow: some View {
        SettingRow(title: Text("Launch at login")) {
            if model.launchAtLogin == .requiresApproval {
                Text("Allow Stay Lit in System Settings, under Login Items.")
                    .captionStyle()
            }
        } control: {
            // Reading `isBusy` re-renders the switch when an action ends, so a failed change snaps
            // it back to the system status; it also stops a second click from queueing behind the first.
            SettingSwitch(
                title: "Launch at login",
                identifier: "launchAtLoginToggle",
                isOn: model.launchAtLogin.isRegistered,
                isDisabled: model.launchAtLogin == .unavailable || model.isBusy,
                set: model.setLaunchAtLogin
            )
        }
    }

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
}
