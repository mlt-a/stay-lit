import Testing
@testable import StayLitCore

struct PmsetOutputTests {
    @Test(arguments: [
        ("System-wide power settings:\n SleepDisabled\t\t1\n", true),
        ("System-wide power settings:\n SleepDisabled\t\t0\n", false),
        // No line at all means sleep is allowed.
        ("Currently in use:\n sleep 1\n displaysleep 10\n", false),
        ("", false),
        // A setting whose name only starts like the one we want.
        (" SleepDisabledSomething 1\n", false),
    ])
    func readsSleepDisabled(output: String, expected: Bool) {
        #expect(PmsetOutput.isSleepDisabled(in: output) == expected)
    }

    @Test func realOutputWithSleepDisabled() {
        #expect(PmsetOutput.isSleepDisabled(in: realOutputSleepDisabled))
    }

    @Test func realOutputWithoutSleepDisabledLine() {
        let output = realOutputSleepDisabled
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("SleepDisabled") }
            .joined(separator: "\n")
        #expect(!PmsetOutput.isSleepDisabled(in: output))
    }
}

/// Output of `pmset -g` captured on a Mac while sleep was disabled.
private let realOutputSleepDisabled = """
    System-wide power settings:
     SleepDisabled\t\t1
    Currently in use:
     standby              1
     Sleep On Power Button 1
     hibernatefile        /var/vm/sleepimage
     powernap             1
     networkoversleep     0
     disksleep            10
     sleep                1 (sleep prevented by coreaudiod, caffeinate, caffeinate, sharingd, Google Chrome, powerd)
     hibernatemode        3
     ttyskeepawake        1
     displaysleep         10 (display sleep prevented by Google Chrome)
     tcpkeepalive         1
     powermode            0
     womp                 0

    """
