import Foundation

/// Locks the session now. The app target composes the real implementation, tests use a double.
public protocol ScreenLocking: Sendable {
    /// Throws `ScreenLockError.unavailable` when the system function cannot be found.
    func lockScreen() throws
}

public enum ScreenLockError: Error, Equatable, Sendable {
    /// The private framework or its function is missing: a macOS update may have removed it.
    case unavailable
}

/// `SACLockScreenImmediate` from the private `login.framework`, found at run time so that a
/// missing symbol is an error to show, not a crash at launch.
public struct LoginFrameworkScreenLocker: ScreenLocking {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
    private static let symbolName = "SACLockScreenImmediate"

    public init() {}

    public func lockScreen() throws {
        guard let handle = dlopen(Self.frameworkPath, RTLD_NOW),
            let symbol = dlsym(handle, Self.symbolName)
        else { throw ScreenLockError.unavailable }
        let lock = unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
        // The return value is ignored: its meaning is not documented.
        _ = lock()
    }
}
