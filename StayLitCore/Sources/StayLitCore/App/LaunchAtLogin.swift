public enum LaunchAtLoginStatus: Sendable, Equatable {
    case enabled
    case disabled
    /// Registered, but the user still has to allow the item in System Settings.
    case requiresApproval
    /// The system cannot register this app (for example, it runs outside an app bundle).
    case unavailable

    /// The app is registered, approved or not: the "Launch at login" box shows as checked.
    public var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}

/// Registers the app to open when the user logs in.
/// The app target implements it with `SMAppService`: the core does not import ServiceManagement.
public protocol LaunchAtLoginControlling: Sendable {
    /// Read from the system every time. The app keeps no copy of its own.
    var status: LaunchAtLoginStatus { get }

    /// Throws the system's error when the registration fails.
    func setEnabled(_ enabled: Bool) throws
}
