import Testing
@testable import StayLitCore

struct ClaudeActivityTests {
    @Test(arguments: [
        ("busy" as String?, ClaudeActivity.working),
        ("shell", .working),
        ("idle", .idle),
        ("waiting", .waiting),
        ("compacting", .working),
        (nil, .working),
    ])
    func eachStatusMapsToAnActivity(status: String?, activity: ClaudeActivity) {
        #expect(ClaudeActivity(status: status) == activity)
    }
}
