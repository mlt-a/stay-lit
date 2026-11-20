/// What the window says about a block that ended without the user asking.
public enum BlockEndNotice: Sendable, Equatable {
    /// The run with the lid closed. It already carries the reason of an automatic restore, so it
    /// wins over the restore notice.
    case lidClosedReport(LidClosedReport)
    /// Why the app allowed sleep again by itself. Never the timer: the user chose the duration,
    /// and the state sentence says enough.
    case automaticRestore(RestoreReason)

    /// `nil` when there is nothing to say.
    init?(report: LidClosedReport?, restore: RestoreReason?) {
        if let report {
            self = .lidClosedReport(report)
        } else if let restore, restore != .timer {
            self = .automaticRestore(restore)
        } else {
            return nil
        }
    }

    /// How the block ended. A restore without a report ends like a report of that restore.
    public var end: LidClosedReport.End {
        switch self {
        case .lidClosedReport(let report): report.end
        case .automaticRestore(let reason): .restored(reason)
        }
    }

    /// The app's reason for allowing sleep again, when the notice gives one.
    public var restoreReason: RestoreReason? {
        if case .restored(let reason) = end { reason } else { nil }
    }

    /// The guard that cut the block short. `nil` when the block ended as planned.
    public var interruptingGuard: RestoreReason.Kind? {
        end.endedAsPlanned ? nil : restoreReason?.kind
    }
}
