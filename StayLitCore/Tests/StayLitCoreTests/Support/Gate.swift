/// Holds a fake call until the test opens it, so a test can act while the call is in flight
/// without waiting for real time.
actor Gate {
    private var isOpen = false
    private var hasArrived = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []

    /// Called by the fake: returns once the gate is open.
    func pass() async {
        hasArrived = true
        watchers.forEach { $0.resume() }
        watchers.removeAll()
        guard !isOpen else { return }
        await withCheckedContinuation { held.append($0) }
    }

    /// Returns once a call is held at the gate.
    func waitUntilArrived() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { watchers.append($0) }
    }

    func open() {
        isOpen = true
        held.forEach { $0.resume() }
        held.removeAll()
    }
}
