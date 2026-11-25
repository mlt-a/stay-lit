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

    @Test(arguments: ["idle", "waiting", "busy", nil] as [String?])
    func aSessionUnderRemoteControlWorks(status: String?) {
        #expect(ClaudeActivity(status: status, bridgeSessionId: "session_01abc") == .working)
    }

    @Test func anEmptyBridgeIsNotRemoteControl() {
        #expect(ClaudeActivity(status: "idle", bridgeSessionId: "") == .idle)
    }
}
