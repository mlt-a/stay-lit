@testable import StayLitCore

/// A lid the test opens and closes by hand.
final class FakeLidReader: LidReading, Sendable {
    private let closed: LockedValue<Bool>

    init(isClosed: Bool = false) {
        closed = LockedValue(isClosed)
    }

    var isClosed: Bool {
        get { closed.value }
        set { closed.value = newValue }
    }

    func isLidClosed() -> Bool { isClosed }
}
