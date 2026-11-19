@testable import StayLitCore

/// Counts the requests to sleep and never sleeps the Mac. `error` makes every call fail.
final class FakeSystemSleeper: SystemSleeping, Sendable {
    private let calls = LockedValue(0)
    private let failure: (any Error)?

    init(error: (any Error)? = nil) {
        failure = error
    }

    var sleepNowCount: Int { calls.value }

    func sleepNow() async throws {
        calls.withLock { $0 += 1 }
        if let failure { throw failure }
    }
}
