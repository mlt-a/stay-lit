import StayLitCore
import SwiftUI

/// "Last time I stayed lit": how the last block ended by itself. Green when it ended as planned,
/// amber when something cut it short.
struct LastRunSection: View {
    let notice: BlockEndNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last time I stayed lit")
                .sectionHeaderStyle()
            Notice(symbol: notice.end.symbol, tint: tint) {
                VStack(alignment: .leading, spacing: 2) {
                    if case .lidClosedReport(let report) = notice {
                        Text("I ran \(report.formattedDuration) with the lid closed")
                    }
                    Text(notice.end.cause)
                }
                .accessibilityIdentifier("lastRunReport")
            }
        }
    }

    private var tint: Color {
        notice.end.endedAsPlanned ? Color(.textGreen) : Color(.textAmber)
    }
}

private extension LidClosedReport {
    /// A run lasts at least a minute, so hours and minutes never format to an empty string.
    var formattedDuration: String {
        duration.formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

private extension LidClosedReport.End {
    var cause: String {
        switch self {
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
        switch self {
        case .restored(let reason): reason.kind.symbol
        case .lidOpened: "laptopcomputer"
        case .sleepAllowedElsewhere: "moon"
        case .macSlept: "moon.zzz"
        }
    }
}
