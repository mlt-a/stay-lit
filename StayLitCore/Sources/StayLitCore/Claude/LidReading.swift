import IOKit

/// Tells whether the lid of the Mac is closed. The app target composes the real implementation,
/// tests use a double.
public protocol LidReading: Sendable {
    /// Read from the system every time.
    func isLidClosed() -> Bool
}

/// Reads `AppleClamshellState` on `IOPMrootDomain`. A Mac without a lid has no such property.
public struct IOKitLidReader: LidReading {
    public init() {}

    public func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        // "Create" in the name: the value comes back retained, and we own it.
        let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        return value as? Bool ?? false
    }
}
