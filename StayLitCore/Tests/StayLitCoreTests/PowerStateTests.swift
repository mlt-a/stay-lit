import Foundation
import IOKit.ps
import Testing
@testable import StayLitCore

struct PowerStateTests {
    private func battery(
        state: String = kIOPSBatteryPowerValue,
        current: Int = 57,
        maximum: Int = 100,
        isPresent: Bool? = nil,
        type: String = kIOPSInternalBatteryType
    ) -> [String: Any] {
        var description: [String: Any] = [
            kIOPSTypeKey: type,
            kIOPSPowerSourceStateKey: state,
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: maximum,
        ]
        if let isPresent { description[kIOPSIsPresentKey] = isPresent }
        return description
    }

    @Test func aBatteryInUseIsOnBattery() {
        #expect(PowerState(powerSourceDescription: battery()) == .onBattery(57))
    }

    @Test func aBatteryOnTheChargerIsNotOnBattery() {
        let description = battery(state: kIOPSACPowerValue, current: 80)
        #expect(PowerState(powerSourceDescription: description) == .onACPower(80))
    }

    @Test func theChargeIsAPercentOfTheMaximum() {
        #expect(PowerState(powerSourceDescription: battery(current: 2, maximum: 8)) == .onBattery(25))
    }

    @Test func theChargeStaysBetweenZeroAndOneHundred() {
        #expect(PowerState(powerSourceDescription: battery(current: 120, maximum: 100))?.percent == 100)
        #expect(PowerState(powerSourceDescription: battery(current: -3, maximum: 100))?.percent == 0)
    }

    @Test func aSourceThatIsNotTheInternalBatteryIsIgnored() {
        #expect(PowerState(powerSourceDescription: battery(type: kIOPSUPSType)) == nil)
    }

    @Test func aMissingBatteryIsIgnored() {
        #expect(PowerState(powerSourceDescription: battery(isPresent: false)) == nil)
    }

    @Test func aDescriptionWithoutAChargeIsIgnored() {
        var description = battery()
        description[kIOPSCurrentCapacityKey] = nil
        #expect(PowerState(powerSourceDescription: description) == nil)
        #expect(PowerState(powerSourceDescription: battery(maximum: 0)) == nil)
        #expect(PowerState(powerSourceDescription: [:]) == nil)
    }
}
