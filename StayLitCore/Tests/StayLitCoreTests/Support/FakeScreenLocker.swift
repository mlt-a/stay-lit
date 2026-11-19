@testable import StayLitCore

/// Counts the requests to lock the screen and never locks it. `fails` makes every call throw.
final class FakeScreenLocker: ScreenLocking, Sendable {
    private let calls = LockedValue(0)
    private let failing: LockedValue<Bool>

    init(fails: Bool = false) {
        failing = LockedValue(fails)
    }

    var lockCount: Int { calls.value }

    var fails: Bool {
        get { failing.value }
        set { failing.value = newValue }
    }

    func lockScreen() throws {
        calls.withLock { $0 += 1 }
        if fails { throw ScreenLockError.unavailable }
    }
}
