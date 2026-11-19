import Testing
@testable import StayLitCore

struct BatteryGuardTests {
    @Test(arguments: [
        (PowerState?.some(.onBattery(21)), false),
        (.some(.onBattery(20)), true),
        (.some(.onBattery(19)), true),
        (.some(.onACPower(5)), false),
        (nil, false),
    ])
    func theBatteryIsLowOnBatteryAtTheThresholdOrBelow(power: PowerState?, isLow: Bool) {
        #expect(BatteryGuard.threshold == 20)
        #expect(BatteryGuard.isLow(power) == isLow)
    }
}
