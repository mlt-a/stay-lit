import StayLitCore
import SwiftUI

/// The top of the window: whether the lid can close, the switch that decides it, what the
/// agents are doing, and the last error.
struct LidSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LidEdge(lights: LidLight.row(for: model.claudeSessions), isLit: isLit)
            // Until the first check ends, the switch is shown disabled rather than the panel,
            // so the window does not flash the wrong one.
            switch model.authorization {
            case .notAuthorized:
                VStack(alignment: .leading, spacing: 8) {
                    StateSentence(text: "One permission first.")
                    AuthorizationPanel(model: model)
                }
            case .authorized, nil:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        StateSentence(text: model.isSleepDisabled ? "Close me. I stay lit." : "Close me and I sleep.")
                        Spacer(minLength: 0)
                        SettingSwitch(
                            title: "Stay lit",
                            identifier: "sleepToggle",
                            isOn: model.isSleepDisabled,
                            isDisabled: isSleepSwitchDisabled,
                            controlSize: .large,
                            set: model.setSleepDisabled
                        )
                    }
                    GuardBlockLine(sleepControl: model.sleepControl)
                    AgentsLine(summary: model.claudeSessions.summary(isSleepBlocked: model.isSleepDisabled))
                    if model.isSleepDisabled {
                        SleepDetail(restoreDeadline: model.restoreDeadline)
                    }
                }
            }
            ErrorNotice(model: model)
        }
    }

    /// The lights stay off without the rule: the switch that would light them is not there.
    private var isLit: Bool {
        model.isSleepDisabled && model.authorization != .notAuthorized
    }

    private var isSleepSwitchDisabled: Bool {
        switch model.sleepControl {
        case .available: false
        case .busy, .authorizationUnknown, .blockedByBatteryGuard, .blockedByTemperatureGuard: true
        }
    }
}

private struct StateSentence: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("sleepStatusLabel")
    }
}

/// Why the switch is greyed out while a guard keeps sleep allowed. The guard's own row is
/// further down, out of sight of the switch.
private struct GuardBlockLine: View {
    let sleepControl: SleepControlState

    var body: some View {
        if let block {
            Notice(symbol: block.kind.symbol, tint: Color(.textAmber)) {
                Text(block.text)
                    .accessibilityIdentifier("sleepBlockedLabel")
            }
        }
    }

    private var block: (kind: RestoreReason.Kind, text: String)? {
        switch sleepControl {
        case .blockedByBatteryGuard:
            (.lowBattery, "Battery is low, so I can't stay lit. Plug me in, or turn off \"\(RestoreReason.Kind.lowBattery.settingTitle)\" below.")
        case .blockedByTemperatureGuard:
            (.highTemperature, "I'm too hot to stay lit. Let me cool down, or turn off \"\(RestoreReason.Kind.highTemperature.settingTitle)\" below.")
        case .available, .busy, .authorizationUnknown:
            nil
        }
    }
}

/// What the Claude Code sessions do: words and colors for the summary the core decides.
private struct AgentsLine: View {
    let summary: ClaudeSessionSummary

    var body: some View {
        Group {
            switch summary {
            case .pausedOnClose(let working):
                Label {
                    Text("\(Self.agents(working)) working. Closing the lid pauses \(working == 1 ? "it" : "them").")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(Color(.textAmber))
            case .keptAwake(let working, let waiting):
                Self.line(working: working, waiting: waiting)
                    .foregroundStyle(Color(.textGreen))
            case .noneWorking(let waiting):
                Self.line(working: 0, waiting: waiting)
                    .foregroundStyle(.primary)
            }
        }
        .subheadlineStyle()
        .accessibilityIdentifier("agentsLabel")
    }

    private static func line(working: Int, waiting: Int) -> Text {
        switch (working, waiting) {
        case (0, 0): Text("No agent working")
        case (let working, 0): Text("\(agents(working)) working")
        case (0, let waiting): Text("\(agents(waiting)) waiting for you")
        case (let working, let waiting): Text("\(agents(working)) working, \(waiting) waiting for you")
        }
    }

    /// "1 agent", "2 agents".
    private static func agents(_ count: Int) -> String {
        count == 1 ? "1 agent" : "\(count) agents"
    }
}

/// Shown while sleep is blocked: the lock on close, and how long the block lasts.
private struct SleepDetail: View {
    let restoreDeadline: Date?

    var body: some View {
        Group {
            // The remaining time counts down by itself, with no tick in the model.
            if let restoreDeadline {
                let now = Date.now
                Text("Locks on close. Sleeps again in \(Text(timerInterval: now...max(now, restoreDeadline), countsDown: true))")
            } else {
                Text("Locks on close. Until you turn it off.")
            }
        }
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("sleepDetailLabel")
    }
}
