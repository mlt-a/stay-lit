import Foundation

/// The temperature guard rule. The model composes it with the setting and the sleep state.
public enum TemperatureGuard {
    /// At or above `.serious` the system already throttles. Compared by raw value so a level
    /// added above `.critical` later counts as too hot.
    public static func isTooHot(_ state: ProcessInfo.ThermalState) -> Bool {
        state.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }
}
