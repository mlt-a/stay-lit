import StayLitCore
import SwiftUI

/// What happened that the user did not ask for: the last error, then the lid-closed report,
/// or else why sleep is allowed again.
struct Notices: View {
    let model: AppModel

    var body: some View {
        if let error = model.error {
            Notice(
                symbol: "exclamationmark.octagon",
                tint: Color(.textRed),
                dismiss: NoticeDismissal(identifier: "dismissErrorButton") { model.dismissError() }
            ) {
                Text(error.message)
                    .accessibilityIdentifier("errorMessage")
            }
        }
        switch model.blockEndNotice {
        case .lidClosedReport(let report):
            Notice(
                symbol: report.symbol,
                tint: Color(.textAmber),
                dismiss: NoticeDismissal(identifier: "dismissLidClosedReportButton") { model.dismissLidClosedReport() }
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I ran \(report.formattedDuration) with the lid closed")
                    Text(report.cause)
                }
                .accessibilityIdentifier("lidClosedReport")
            }
        case .automaticRestore(let restore):
            if let notice = RestoreNotice(restore) {
                Notice(symbol: restore.kind.symbol, tint: Color(.textAmber)) {
                    Text(notice.text)
                        .accessibilityIdentifier(notice.identifier)
                }
            }
        case nil:
            EmptyView()
        }
    }
}

/// The button that dismisses a notice.
struct NoticeDismissal {
    let identifier: String
    let action: () -> Void
}

/// A symbol, the text, and the button that dismisses it when there is one.
struct Notice<Content: View>: View {
    let symbol: String
    let tint: Color
    var dismiss: NoticeDismissal?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .frame(width: symbolColumnWidth)
                .accessibilityHidden(true)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button("Dismiss", systemImage: "xmark", action: dismiss.action)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(dismiss.identifier)
            }
        }
        .subheadlineStyle()
        .foregroundStyle(tint)
    }
}

/// The words of a restore notice.
private struct RestoreNotice {
    let text: String
    let identifier: String

    /// `nil` for the timer, which `AppModel.blockEndNotice` never carries.
    init?(_ reason: RestoreReason) {
        switch reason {
        case .lowBattery:
            text = "Battery low, so I can sleep again."
            identifier = "lowBatteryNotice"
        case .highTemperature:
            text = "I got too hot, so I can sleep again."
            identifier = "highTemperatureNotice"
        case .claudeFinished:
            text = "Claude Code finished, so I can sleep again."
            identifier = "claudeFinishedNotice"
        case .timer:
            return nil
        }
    }
}

private extension LidClosedReport {
    /// A run lasts at least a minute, so hours and minutes never format to an empty string.
    var formattedDuration: String {
        duration.formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    var cause: String {
        switch end {
        case .restored(.timer): "Stopped: the timer ended"
        case .restored(.lowBattery(let percent)): "Stopped: battery low (\(percent)%)"
        case .restored(.highTemperature): "Stopped: I got too hot"
        case .restored(.claudeFinished): "Stopped: Claude Code finished"
        case .lidOpened: "Still lit when you opened me"
        case .sleepAllowedElsewhere: "Stopped: sleep allowed outside Stay Lit"
        case .macSlept: "Stopped: I went to sleep anyway"
        }
    }

    var symbol: String {
        switch end {
        case .restored(let reason): reason.kind.symbol
        case .lidOpened: "laptopcomputer"
        case .sleepAllowedElsewhere: "moon"
        case .macSlept: "moon.zzz"
        }
    }
}
