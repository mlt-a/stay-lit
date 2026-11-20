import StayLitCore
import SwiftUI

/// The failure of the last action or refresh, under the switch it concerns, with its dismiss button.
struct ErrorNotice: View {
    let model: AppModel

    var body: some View {
        if let error = model.error {
            Notice(symbol: "exclamationmark.octagon", tint: Color(.textRed)) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(error.message)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("errorMessage")
                    Button("Dismiss", systemImage: "xmark", action: model.dismissError)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dismissErrorButton")
                }
            }
        }
    }
}

/// A symbol in the symbol column, then the text.
struct Notice<Content: View>: View {
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .frame(width: symbolColumnWidth)
                .accessibilityHidden(true)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .subheadlineStyle()
        .foregroundStyle(tint)
    }
}
