import AppKit
import CoreGraphics
import StayLitCore

/// Tells when the Mac is about to sleep and when the user is back after a wake.
///
/// The user is back when a wake finds the screen unlocked, or at the first unlock after a wake
/// that found it locked. Each wake yields one `.resumed`: a later unlock without a new wake
/// yields nothing, and a `.sleeping` before the unlock cancels the wait.
///
/// A wake with the lid closed and the screen locked yields `.resumed` only once someone unlocks.
@MainActor
final class WorkspaceSessionMonitor: SessionMonitoring {
    func events() -> AsyncStream<SessionEvent> {
        // Unbounded: a `.sleeping` and a `.resumed` back to back must both arrive.
        let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self, bufferingPolicy: .unbounded)
        let subscription = Subscription(continuation: continuation)
        // The consumer stopped (its task ended or was cancelled): stop observing.
        continuation.onTermination = { _ in
            Task { @MainActor in subscription.stop() }
        }
        return stream
    }
}

/// The observers behind one stream. It lives on the main actor, like every callback it receives.
@MainActor
private final class Subscription {
    private let continuation: AsyncStream<SessionEvent>.Continuation
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    /// Set while a wake found the screen locked and waits for the unlock.
    private var unlockObserver: NSObjectProtocol?

    init(continuation: AsyncStream<SessionEvent>.Continuation) {
        self.continuation = continuation
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }
    }

    func stop() {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        sleepObserver = nil
        wakeObserver = nil
        stopWaitingForUnlock()
    }

    private func willSleep() {
        stopWaitingForUnlock()
        continuation.yield(.sleeping)
    }

    private func didWake() {
        // A new wake replaces a wait still pending from the previous one.
        stopWaitingForUnlock()
        guard Self.isScreenLocked else {
            continuation.yield(.resumed)
            return
        }
        // Undocumented: macOS posts it to the distributed center when the session unlocks.
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // One `.resumed` per wake.
                self?.stopWaitingForUnlock()
                self?.continuation.yield(.resumed)
            }
        }
    }

    private func stopWaitingForUnlock() {
        if let unlockObserver { DistributedNotificationCenter.default().removeObserver(unlockObserver) }
        unlockObserver = nil
    }

    /// The key is undocumented, like the unlock notification. Absent means not locked.
    private static var isScreenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
