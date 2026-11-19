import Synchronization

/// A value a test double shares with the model's tasks, behind a lock.
final class LockedValue<Value: Sendable>: Sendable {
    private let stored: Mutex<Value>

    init(_ value: Value) {
        stored = Mutex(value)
    }

    var value: Value {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }

    func withLock<Result: Sendable>(_ body: (inout Value) -> Result) -> Result {
        stored.withLock { body(&$0) }
    }
}
