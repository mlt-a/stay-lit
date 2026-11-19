/// Whether the "Block sleep" switch can be used now, and if not, why.
/// The switch is hidden while the rule is missing: the authorization panel replaces it.
public enum SleepControlState: Sendable, Equatable {
    case available
    /// An action of the user is waiting or running.
    case busy
    /// The first check of the authorization has not ended yet.
    case authorizationUnknown
    /// The battery is low and sleep is allowed: blocking it would be undone at once.
    case blockedByBatteryGuard
    /// The Mac is too hot and sleep is allowed: blocking it would be undone at once.
    case blockedByTemperatureGuard
}
