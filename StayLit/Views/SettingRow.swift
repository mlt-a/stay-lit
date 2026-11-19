import SwiftUI

/// The column of the symbols, shared by the setting rows and the notices.
let symbolColumnWidth: CGFloat = 20

/// One setting of the window: an optional symbol, a title over a caption, the control on the right.
struct SettingRow<Caption: View, Control: View>: View {
    var symbol: String?
    /// The condition behind this row is what the window reports right now.
    var isAlerted = false
    let title: Text
    @ViewBuilder let caption: Caption
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.body)
                        .foregroundStyle(.secondary(alerted: isAlerted))
                        .frame(width: symbolColumnWidth)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    title.font(.body)
                    caption
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

extension SettingRow where Caption == EmptyView {
    init(symbol: String? = nil, isAlerted: Bool = false, title: Text, @ViewBuilder control: () -> Control) {
        self.init(symbol: symbol, isAlerted: isAlerted, title: title, caption: { EmptyView() }, control: control)
    }
}

/// The switch of a setting row. Its label is hidden but read by VoiceOver.
struct SettingSwitch: View {
    let title: String
    let identifier: String
    let isOn: Bool
    let isDisabled: Bool
    var controlSize = ControlSize.mini
    let set: (Bool) async -> Void

    var body: some View {
        Toggle(
            title,
            isOn: Binding(
                get: { isOn },
                set: { enabled in Task { await set(enabled) } }
            )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(controlSize)
        .disabled(isDisabled)
        .accessibilityIdentifier(identifier)
    }
}
