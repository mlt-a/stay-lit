/// Why the app allowed sleep again without being asked.
public enum RestoreReason: Sendable, Equatable {
    /// The chosen block duration ran out.
    case timer
    /// The battery guard acted: the Mac ran on battery at `percent`, at or below the threshold.
    case lowBattery(percent: Int)
    /// The temperature guard acted: the thermal state reached `.serious` or more.
    case highTemperature
    /// The Claude guard acted: no Claude Code session works any more and the lid is closed.
    case claudeFinished
}

extension RestoreReason {
    /// The sort of reason, without its details.
    public enum Kind: Sendable, Hashable {
        case timer
        case lowBattery
        case highTemperature
        case claudeFinished

        /// The SF Symbol of the condition, shared by its setting row and its notices.
        public var symbol: String {
            switch self {
            case .timer: "timer"
            case .lowBattery: "battery.25percent"
            case .highTemperature: "thermometer.high"
            case .claudeFinished: "terminal"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .timer: .timer
        case .lowBattery: .lowBattery
        case .highTemperature: .highTemperature
        case .claudeFinished: .claudeFinished
        }
    }

    /// The Mac is put to sleep right after sleep is allowed: the user closed the lid and left.
    var followsWithSystemSleep: Bool {
        self == .claudeFinished
    }
}
