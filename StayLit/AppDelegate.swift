import AppKit
import StayLitCore
import SwiftUI

/// Owns the app's lifecycle: it starts watching the system at launch and turns sleep back on
/// before quitting, which only the delegate hears about.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let notifier = UserNotificationSleepRestoreNotifier()
    private var isQuitting = false

    /// Where the "Battery guard" setting lives between launches. Missing means on.
    private static let batteryGuardKey = "batteryGuardEnabled"
    /// Where the "Temperature guard" setting lives between launches. Missing means on.
    private static let temperatureGuardKey = "temperatureGuardEnabled"
    /// Where the "Claude guard" setting lives between launches. Missing means off: it puts the Mac to sleep.
    private static let claudeGuardKey = "claudeGuardEnabled"
    /// Where the chosen block duration lives between launches, as its raw value. Missing or unknown means until turned off.
    private static let blockDurationKey = "blockDuration"

    #if DEBUG
    /// Set by `-demo <state>`: the window shows that state, on doubles, and no command runs.
    private let demo = DemoState.launchArgument.map { DemoMac($0) }
    private var demoWindow: NSWindow?
    #endif

    override init() {
        #if DEBUG
        if let demo {
            model = demo.model
        } else {
            model = Self.liveModel(notifier: notifier)
        }
        #else
        model = Self.liveModel(notifier: notifier)
        #endif
        super.init()
    }

    /// What the window calls to ask for the right to notify. The demo never asks.
    var requestNotificationPermission: () -> Void {
        #if DEBUG
        if demo != nil { return {} }
        #endif
        return notifier.requestPermission
    }

    private static func liveModel(notifier: UserNotificationSleepRestoreNotifier) -> AppModel {
        AppModel(
            sleepController: SleepController(),
            authorizer: SudoersAuthorizer(prompts: .standard),
            launchAtLogin: MainAppLaunchAtLogin(),
            powerMonitor: IOKitPowerMonitor(),
            thermalMonitor: ProcessInfoThermalMonitor(),
            claudeSessions: ClaudeSessionDirectoryReader(),
            lid: IOKitLidReader(),
            systemSleeper: PmsetSystemSleeper(),
            screenLocker: LoginFrameworkScreenLocker(),
            notifier: notifier,
            isBatteryGuardEnabled: UserDefaults.standard.object(forKey: Self.batteryGuardKey) as? Bool ?? true,
            onBatteryGuardChange: { enabled in
                UserDefaults.standard.set(enabled, forKey: Self.batteryGuardKey)
                // Asked when the user turns the guard on, and when the window opens with it on.
                if enabled { notifier.requestPermission() }
            },
            isTemperatureGuardEnabled: UserDefaults.standard.object(forKey: Self.temperatureGuardKey) as? Bool ?? true,
            onTemperatureGuardChange: { enabled in
                UserDefaults.standard.set(enabled, forKey: Self.temperatureGuardKey)
                if enabled { notifier.requestPermission() }
            },
            isClaudeGuardEnabled: UserDefaults.standard.object(forKey: Self.claudeGuardKey) as? Bool ?? false,
            onClaudeGuardChange: { enabled in
                UserDefaults.standard.set(enabled, forKey: Self.claudeGuardKey)
                if enabled { notifier.requestPermission() }
            },
            blockDuration: UserDefaults.standard.string(forKey: Self.blockDurationKey)
                .flatMap(BlockDuration.init(rawValue:)) ?? .untilTurnedOff,
            onBlockDurationChange: { duration in
                UserDefaults.standard.set(duration.rawValue, forKey: Self.blockDurationKey)
            }
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let demo {
            Task { await demo.prepare() }
            showDemoWindow()
            return
        }
        #endif
        model.startMonitoring()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // AppKit gets one reply only, from the first request.
        guard !isQuitting else { return .terminateLater }
        isQuitting = true
        Task {
            await model.allowSleepBeforeQuitting()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

#if DEBUG
extension AppDelegate {
    /// The demo also opens an ordinary window, so a screenshot tool finds it without a click
    /// in the menu bar.
    private func showDemoWindow() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: StatusView(model: model)))
        window.title = "Stay Lit demo"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // `-demoAppearance light|dark` pins the look, so captures do not follow the system.
        switch UserDefaults.standard.string(forKey: "demoAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        demoWindow = window
    }
}
#endif

private extension AuthorizationPrompts {
    /// What the macOS password dialog says. It states what Stay Lit is about to do.
    static var standard: AuthorizationPrompts {
        AuthorizationPrompts(
            install: "Stay Lit wants to add a rule that lets it turn sleep off and on without asking for your password again.",
            remove: "Stay Lit wants to turn sleep back on and remove its rule."
        )
    }
}
