import StayLitCore
import SwiftUI

/// "Let me sleep when": the conditions that end a block, one row each.
struct SleepConditionsSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Let me sleep when")
                .sectionHeaderStyle()
            GuardRow(
                condition: .claudeFinished,
                identifier: "claudeGuard",
                reported: reported,
                isOn: model.isClaudeGuardEnabled,
                isDisabled: model.isBusy,
                set: model.setClaudeGuardEnabled
            )
            SettingRow(symbol: RestoreReason.Kind.timer.symbol, title: Text(RestoreReason.Kind.timer.settingTitle)) {
                DurationPicker(model: model)
            }
            if model.hasBattery {
                GuardRow(
                    condition: .lowBattery,
                    caption: "On battery only.",
                    identifier: "batteryGuard",
                    isBlocking: model.sleepControl == .blockedByBatteryGuard,
                    reported: reported,
                    isOn: model.isBatteryGuardEnabled,
                    isDisabled: model.isBusy,
                    set: model.setBatteryGuardEnabled
                )
            }
            GuardRow(
                condition: .highTemperature,
                caption: "When macOS reports serious heat.",
                identifier: "temperatureGuard",
                isBlocking: model.sleepControl == .blockedByTemperatureGuard,
                reported: reported,
                isOn: model.isTemperatureGuardEnabled,
                isDisabled: model.isBusy,
                set: model.setTemperatureGuardEnabled
            )
        }
    }

    /// The guard that cut the last block short, until a new block starts.
    private var reported: RestoreReason.Kind? {
        model.isSleepDisabled ? nil : model.blockEndNotice?.interruptingGuard
    }
}

extension RestoreReason.Kind {
    /// The title of the condition's row, also quoted by the message under the main switch.
    var settingTitle: String {
        switch self {
        case .claudeFinished: "Claude Code is done"
        case .timer: "Time is up"
        case .lowBattery: "Battery at \(BatteryGuard.threshold)% or less"
        case .highTemperature: "I get too hot"
        }
    }
}

/// The row of a guard: its switch and an optional caption. The row turns amber while the
/// guard keeps sleep allowed; the message under the main switch says why. Its identifiers are
/// `identifier` followed by `Caption` and `Toggle`.
private struct GuardRow: View {
    let condition: RestoreReason.Kind
    var caption: String?
    let identifier: String
    var isBlocking = false
    let reported: RestoreReason.Kind?
    let isOn: Bool
    let isDisabled: Bool
    let set: (Bool) async -> Void

    var body: some View {
        SettingRow(symbol: condition.symbol, isAlerted: isBlocking || reported == condition, title: Text(condition.settingTitle)) {
            if let caption {
                Text(caption)
                    .captionStyle()
                    .accessibilityIdentifier("\(identifier)Caption")
            }
        } control: {
            SettingSwitch(
                title: condition.settingTitle,
                identifier: "\(identifier)Toggle",
                isOn: isOn,
                isDisabled: isDisabled,
                set: set
            )
        }
    }
}
