import Foundation
import Testing
@testable import StayLitCore

struct TemperatureGuardTests {
    @Test(arguments: [
        (ProcessInfo.ThermalState.nominal, false),
        (.fair, false),
        (.serious, true),
        (.critical, true),
    ])
    func theMacIsTooHotFromSeriousUp(state: ProcessInfo.ThermalState, isTooHot: Bool) {
        #expect(TemperatureGuard.isTooHot(state) == isTooHot)
    }
}
