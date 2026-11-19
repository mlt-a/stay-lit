import Foundation
@testable import StayLitCore

/// A battery the test drives by hand: `send` changes the state and tells every subscriber,
/// `changeWithoutEvent` changes it alone, as when the system misses an event.
@MainActor
final class FakePowerMonitor: PowerMonitoring {
    private(set) var state: PowerState?
    private var continuations: [AsyncStream<PowerState?>.Continuation] = []
    private let streamEnds: Bool

    /// `streamEnds`: every stream finishes at once, as when the system gives no event source.
    init(_ state: PowerState? = nil, streamEnds: Bool = false) {
        self.state = state
        self.streamEnds = streamEnds
    }

    func changes() -> AsyncStream<PowerState?> {
        let (stream, continuation) = AsyncStream.makeStream(of: PowerState?.self, bufferingPolicy: .bufferingNewest(1))
        if streamEnds {
            continuation.finish()
        } else {
            continuations.append(continuation)
        }
        return stream
    }

    func changeWithoutEvent(_ state: PowerState?) {
        self.state = state
    }

    func send(_ state: PowerState?) {
        self.state = state
        continuations.forEach { $0.yield(state) }
    }
}

extension PowerState {
    static func onBattery(_ percent: Int) -> PowerState { PowerState(isOnBattery: true, percent: percent) }
    static func onACPower(_ percent: Int) -> PowerState { PowerState(isOnBattery: false, percent: percent) }
}
