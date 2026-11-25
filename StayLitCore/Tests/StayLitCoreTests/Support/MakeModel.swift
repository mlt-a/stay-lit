@testable import StayLitCore

/// The one way tests build a model. Every dependency is a double; pass the ones the test drives.
/// Time only moves by hand, and the periodic refresh never comes during a test.
@MainActor
func makeModel(
    _ system: FakeSystem = FakeSystem(),
    launchAtLogin: FakeLaunchAtLogin = FakeLaunchAtLogin(),
    power: FakePowerMonitor = FakePowerMonitor(),
    thermal: FakeThermalMonitor = FakeThermalMonitor(),
    session: FakeSessionMonitor = FakeSessionMonitor(),
    claudeSessions: FakeClaudeSessionReader = FakeClaudeSessionReader(),
    lid: FakeLidReader = FakeLidReader(),
    systemSleeper: FakeSystemSleeper = FakeSystemSleeper(),
    screenLocker: FakeScreenLocker = FakeScreenLocker(),
    notifier: FakeSleepRestoreNotifier = FakeSleepRestoreNotifier(),
    batteryGuardEnabled: Bool = true,
    onBatteryGuardChange: @escaping @MainActor (Bool) -> Void = { _ in },
    temperatureGuardEnabled: Bool = true,
    onTemperatureGuardChange: @escaping @MainActor (Bool) -> Void = { _ in },
    claudeGuardEnabled: Bool = true,
    onClaudeGuardChange: @escaping @MainActor (Bool) -> Void = { _ in },
    blockDuration: BlockDuration = .untilTurnedOff,
    onBlockDurationChange: @escaping @MainActor (BlockDuration) -> Void = { _ in },
    time: ManualTimeSource = ManualTimeSource()
) -> AppModel {
    AppModel(
        sleepController: system,
        authorizer: system,
        launchAtLogin: launchAtLogin,
        powerMonitor: power,
        thermalMonitor: thermal,
        sessionMonitor: session,
        claudeSessions: claudeSessions,
        lid: lid,
        systemSleeper: systemSleeper,
        screenLocker: screenLocker,
        notifier: notifier,
        isBatteryGuardEnabled: batteryGuardEnabled,
        onBatteryGuardChange: onBatteryGuardChange,
        isTemperatureGuardEnabled: temperatureGuardEnabled,
        onTemperatureGuardChange: onTemperatureGuardChange,
        isClaudeGuardEnabled: claudeGuardEnabled,
        onClaudeGuardChange: onClaudeGuardChange,
        blockDuration: blockDuration,
        onBlockDurationChange: onBlockDurationChange,
        timeSource: time,
        refreshInterval: .seconds(3600)
    )
}
