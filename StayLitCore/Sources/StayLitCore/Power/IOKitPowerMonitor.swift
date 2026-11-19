import IOKit.ps

/// Reads the battery through IOKit and listens to its changes on the main run loop.
@MainActor
public final class IOKitPowerMonitor: PowerMonitoring {
    public init() {}

    public var state: PowerState? { Self.readState() }

    public func changes() -> AsyncStream<PowerState?> {
        let (stream, continuation) = AsyncStream.makeStream(of: PowerState?.self, bufferingPolicy: .bufferingNewest(1))
        let listener = PowerSourceListener(continuation: continuation)
        guard listener.start() else {
            // No source, so no event will ever come: end the stream rather than leave it open.
            // The model still reads the battery at each refresh.
            continuation.finish()
            return stream
        }
        // The consumer stopped (its task ended or was cancelled): release the run loop source.
        continuation.onTermination = { _ in
            Task { @MainActor in listener.stop() }
        }
        return stream
    }

    /// Follows the Create/Copy/Get rule of Core Foundation: the info and the list are copies we
    /// own (`takeRetainedValue`), each description is borrowed from the info (`takeUnretainedValue`).
    static func readState() -> PowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let state = PowerState(powerSourceDescription: description)
            else { continue }
            return state
        }
        return nil
    }
}

/// One run loop source and the stream it feeds. IOKit calls back on the main run loop,
/// where the main actor runs.
@MainActor
private final class PowerSourceListener {
    private let continuation: AsyncStream<PowerState?>.Continuation
    private var source: CFRunLoopSource?
    /// The C callback holds the listener through a raw pointer: this retain keeps it alive
    /// until `stop` removes the source.
    private var retainedByCallback: Unmanaged<PowerSourceListener>?

    init(continuation: AsyncStream<PowerState?>.Continuation) {
        self.continuation = continuation
    }

    /// `false` when IOKit gave no source: nothing stays retained then.
    func start() -> Bool {
        let context = Unmanaged.passRetained(self)
        // "Create" in the name: the source comes back retained, and we own it.
        guard let source = IOPSNotificationCreateRunLoopSource(powerSourceDidChange, context.toOpaque())?.takeRetainedValue() else {
            context.release()
            return false
        }
        retainedByCallback = context
        self.source = source
        // Common modes: the callback must also fire while the menu bar window tracks events.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func publish() {
        continuation.yield(IOKitPowerMonitor.readState())
    }

    /// Removes the source from the run loop, then lets go of what the callback held.
    /// Safe to call twice.
    func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFRunLoopSourceInvalidate(source)
        self.source = nil
        // The stream's termination handler holds this listener: cut that loop.
        continuation.onTermination = nil
        retainedByCallback?.release()
        retainedByCallback = nil
    }
}

/// The IOKit callback. A C function pointer cannot capture, so the listener travels in `context`.
private func powerSourceDidChange(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    // Borrowed: `retainedByCallback` owns the retain, released in `stop`.
    let listener = Unmanaged<PowerSourceListener>.fromOpaque(context).takeUnretainedValue()
    // The source sits on the main run loop: this runs on the main thread.
    MainActor.assumeIsolated {
        listener.publish()
    }
}
