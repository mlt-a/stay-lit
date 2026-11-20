import Testing
@testable import StayLitCore

struct BlockEndNoticeTests {
    private static func report(_ end: LidClosedReport.End) -> LidClosedReport {
        LidClosedReport(duration: .seconds(600), end: end)
    }

    @Test func nothingToSayWithoutReportOrRestore() {
        #expect(BlockEndNotice(report: nil, restore: nil) == nil)
    }

    @Test(arguments: [RestoreReason.lowBattery(percent: 18), .highTemperature, .claudeFinished])
    func anAutomaticRestoreHasItsNotice(reason: RestoreReason) {
        let notice = BlockEndNotice(report: nil, restore: reason)

        #expect(notice == .automaticRestore(reason))
        #expect(notice?.restoreReason == reason)
    }

    @Test func theTimerHasNoNotice() {
        #expect(BlockEndNotice(report: nil, restore: .timer) == nil)
    }

    @Test(arguments: [RestoreReason.timer, .lowBattery(percent: 18), .highTemperature, .claudeFinished])
    func theReportWinsOverTheRestoreNotice(reason: RestoreReason) {
        let report = Self.report(.restored(reason))
        let notice = BlockEndNotice(report: report, restore: reason)

        #expect(notice == .lidClosedReport(report))
        #expect(notice?.restoreReason == reason)
    }

    @Test(arguments: [LidClosedReport.End.lidOpened, .sleepAllowedElsewhere, .macSlept])
    func aReportThatDidNotEndInARestoreGivesNoReason(end: LidClosedReport.End) {
        let report = Self.report(end)
        let notice = BlockEndNotice(report: report, restore: .highTemperature)

        #expect(notice == .lidClosedReport(report))
        #expect(notice?.restoreReason == nil)
    }

    @Test(arguments: [
        (LidClosedReport.End.restored(.timer), true),
        (.restored(.claudeFinished), true),
        (.lidOpened, true),
        (.restored(.lowBattery(percent: 18)), false),
        (.restored(.highTemperature), false),
        (.sleepAllowedElsewhere, false),
        (.macSlept, false),
    ])
    func onlyAPlannedEndCountsAsPlanned(end: LidClosedReport.End, planned: Bool) {
        #expect(end.endedAsPlanned == planned)
    }

    @Test func aGuardThatCutTheBlockShortIsNamed() {
        let restore = BlockEndNotice.automaticRestore(.highTemperature)
        let report = BlockEndNotice.lidClosedReport(Self.report(.restored(.lowBattery(percent: 18))))

        #expect(restore.interruptingGuard == .highTemperature)
        #expect(report.interruptingGuard == .lowBattery)
    }

    @Test(arguments: [LidClosedReport.End.restored(.timer), .restored(.claudeFinished), .lidOpened, .macSlept])
    func noGuardIsNamedWhenNoneCutTheBlockShort(end: LidClosedReport.End) {
        #expect(BlockEndNotice.lidClosedReport(Self.report(end)).interruptingGuard == nil)
    }

    @Test func aRestoreWithoutReportEndsAsThatRestore() {
        #expect(BlockEndNotice.automaticRestore(.claudeFinished).end == .restored(.claudeFinished))
    }
}
