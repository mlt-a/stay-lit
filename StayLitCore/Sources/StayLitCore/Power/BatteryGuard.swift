/// The battery guard rule. The model composes it with the setting and the sleep state.
public enum BatteryGuard {
    /// The charge, in percent, at or below which the guard acts.
    public static let threshold = 20

    /// On battery and at or below the threshold. A Mac without battery is never low.
    public static func isLow(_ power: PowerState?) -> Bool {
        guard let power else { return false }
        return power.isOnBattery && power.percent <= threshold
    }
}
