import XCTest

/// Every test launches the app with `-demo`: doubles only, so no `sudo`, `pmset` or `osascript` runs.
nonisolated final class StayLitUITests: XCTestCase {
    private static let states = [
        "asleep", "asleepAgents", "lit", "litAgents",
        "unauthorized", "report", "blockedBattery", "tooHot",
    ]
    private static let appearances = ["light", "dark"]

    @MainActor
    private func launchDemo(_ state: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-demo", state, "-demoAppearance", appearance]
        app.launch()
        // The app is an agent (no Dock icon): without this, the window can stay behind other apps
        // and a window screenshot shows whatever covers it.
        app.activate()
        return app
    }

    @MainActor
    func testCaptureDemoStates() {
        continueAfterFailure = false
        for state in Self.states {
            for appearance in Self.appearances {
                let app = launchDemo(state, appearance: appearance)
                let window = app.windows["Stay Lit demo"]
                XCTAssertTrue(window.waitForExistence(timeout: 10), "\(state)-\(appearance)")
                // Lets the entrance animation settle before the capture.
                Thread.sleep(forTimeInterval: 2)
                let shot = XCTAttachment(screenshot: window.screenshot())
                shot.name = "\(state)-\(appearance)"
                shot.lifetime = .keepAlways
                add(shot)
                app.terminate()
            }
        }
    }

    @MainActor
    func testIdentifiersOnLitAgents() {
        continueAfterFailure = false
        let app = launchDemo("litAgents", appearance: "light")
        defer { app.terminate() }
        XCTAssertTrue(app.windows["Stay Lit demo"].waitForExistence(timeout: 10))
        let identifiers = [
            "sleepStatusLabel", "sleepToggle", "agentsLabel", "sleepDetailLabel",
            "claudeGuardToggle", "durationPicker", "batteryGuardToggle",
            "temperatureGuardToggle", "launchAtLoginToggle",
            "removeAuthorizationButton", "quitButton",
        ]
        for identifier in identifiers {
            let element = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(identifier)")
        }
    }
}
