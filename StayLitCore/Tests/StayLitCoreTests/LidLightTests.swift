import Testing
@testable import StayLitCore

struct LidLightTests {
    @Test func noSessionIsOneSteadyLight() {
        #expect(LidLight.row(for: .none) == [.steady])
    }

    @Test func workingLightsComeBeforeWaitingOnes() {
        #expect(LidLight.row(for: ClaudeSessionCounts(working: 2, waiting: 1)) == [.working, .working, .waiting])
    }

    @Test func waitingSessionsAloneLightUp() {
        #expect(LidLight.row(for: ClaudeSessionCounts(waiting: 2)) == [.waiting, .waiting])
    }

    @Test func workingSessionsFillTheEdgeFirst() {
        let row = LidLight.row(for: ClaudeSessionCounts(working: 9, waiting: 3))

        #expect(row == Array(repeating: .working, count: LidLight.maximumCount))
    }

    @Test func waitingSessionsTakeWhatIsLeft() {
        let row = LidLight.row(for: ClaudeSessionCounts(working: 4, waiting: 5))

        #expect(row == [.working, .working, .working, .working, .waiting, .waiting])
    }
}
