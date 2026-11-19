import Foundation

/// Follows one run of the Mac with the lid closed and sleep blocked. The model feeds it every
/// sleep reading, every failed one and every automatic restore, and it returns the report when
/// the run ends.
public struct LidClosedRunTracker: Sendable {
    /// A shorter run is noise: no report.
    public static let minimumDuration: TimeInterval = 60
    /// A longer silence between two readings means the Mac slept.
    public static let sleepGap: TimeInterval = 120

    private struct Run {
        let start: Date
        var lastSeen: Date
    }

    private var run: Run?

    public init() {}

    public var isRunning: Bool { run != nil }

    public mutating func record(lidClosed: Bool, sleepBlocked: Bool, at date: Date) -> LidClosedReport? {
        var report: LidClosedReport?
        if let current = run {
            if let ending = Self.ending(of: current, lidClosed: lidClosed, sleepBlocked: sleepBlocked, at: date) {
                run = nil
                report = Self.report(from: current.start, to: ending.at, because: ending.reason)
            } else {
                run?.lastSeen = date
            }
        }
        // After a gap the same reading may start the next run.
        if run == nil, lidClosed, sleepBlocked {
            run = Run(start: date, lastSeen: date)
        }
        return report
    }

    public mutating func restored(_ reason: RestoreReason, at date: Date) -> LidClosedReport? {
        guard let current = run else { return nil }
        run = nil
        // A restore that lands right after a wake-up did not stop the Mac: the sleep did.
        if let slept = Self.sleepEnding(of: current, at: date) {
            return Self.report(from: current.start, to: slept.at, because: slept.reason)
        }
        return Self.report(from: current.start, to: date, because: .restored(reason))
    }

    /// A failed reading still proves the Mac is awake, so a run of failures is not taken for a
    /// sleep. It neither starts nor ends a run. After a gap it proves nothing: the sleep stays
    /// visible to the next reading.
    public mutating func sawAwake(at date: Date) {
        guard let current = run, Self.sleepEnding(of: current, at: date) == nil else { return }
        run?.lastSeen = date
    }

    /// Drops the run without a report: the user ended it themselves.
    public mutating func cancel() {
        run = nil
    }

    /// When and why the run ends at this reading, if it does. A gap wins: the run ended at the
    /// last reading seen, not at the wake-up. Sleep allowed wins over the lid opening.
    private static func ending(
        of run: Run, lidClosed: Bool, sleepBlocked: Bool, at date: Date
    ) -> (at: Date, reason: LidClosedReport.End)? {
        if let slept = sleepEnding(of: run, at: date) { return slept }
        if !sleepBlocked { return (date, .sleepAllowedElsewhere) }
        if !lidClosed { return (date, .lidOpened) }
        return nil
    }

    /// The one sleep rule: a silence longer than `sleepGap` ends the run at the last reading seen.
    private static func sleepEnding(of run: Run, at date: Date) -> (at: Date, reason: LidClosedReport.End)? {
        date.timeIntervalSince(run.lastSeen) > sleepGap ? (run.lastSeen, .macSlept) : nil
    }

    private static func report(from start: Date, to finish: Date, because reason: LidClosedReport.End) -> LidClosedReport? {
        let seconds = finish.timeIntervalSince(start)
        guard seconds >= minimumDuration else { return nil }
        return LidClosedReport(duration: .seconds(seconds), end: reason)
    }
}
