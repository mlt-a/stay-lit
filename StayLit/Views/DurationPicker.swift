import StayLitCore
import SwiftUI

/// Chooses how long sleep stays blocked. Changing it while sleep is blocked restarts the timer.
/// The battery guard leaves it alone: a duration can be chosen before plugging in.
struct DurationPicker: View {
    let model: AppModel

    var body: some View {
        Picker(
            "Duration",
            selection: Binding(
                get: { model.blockDuration },
                set: { model.setBlockDuration($0) }
            )
        ) {
            ForEach(BlockDuration.allCases, id: \.self) { duration in
                segment(duration)
                    .accessibilityLabel(duration.spokenLabel)
                    .tag(duration)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .fixedSize()
        .disabled(model.isBusy || model.authorization == nil)
        .accessibilityIdentifier("durationPicker")
    }

    /// Short, so four segments fit beside the title.
    @ViewBuilder private func segment(_ duration: BlockDuration) -> some View {
        switch duration {
        case .untilTurnedOff: Image(systemName: "infinity")
        case .oneHour: Text("1 h")
        case .twoHours: Text("2 h")
        case .fourHours: Text("4 h")
        }
    }
}

private extension BlockDuration {
    /// What VoiceOver reads.
    var spokenLabel: String {
        switch self {
        case .untilTurnedOff: "Until turned off"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        }
    }
}
