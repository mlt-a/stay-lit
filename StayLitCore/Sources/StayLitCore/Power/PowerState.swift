import Foundation
import IOKit.ps

/// What the battery reports: whether the Mac runs on it, and how full it is.
public struct PowerState: Sendable, Equatable {
    public var isOnBattery: Bool
    /// 0 to 100.
    public var percent: Int

    public init(isOnBattery: Bool, percent: Int) {
        self.isOnBattery = isOnBattery
        self.percent = percent
    }
}

extension PowerState {
    /// Reads the description IOKit gives for one power source (`IOPSGetPowerSourceDescription`).
    /// `nil` unless it describes the Mac's own battery, present and with a readable charge:
    /// a UPS or a battery bay without a battery says nothing about the Mac running dry.
    init?(powerSourceDescription description: [String: Any]) {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              description[kIOPSIsPresentKey] as? Bool ?? true,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int,
              maximum > 0
        else { return nil }
        let percent = (Double(current) / Double(maximum) * 100).rounded()
        self.init(
            isOnBattery: description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
            percent: min(100, max(0, Int(percent)))
        )
    }
}
