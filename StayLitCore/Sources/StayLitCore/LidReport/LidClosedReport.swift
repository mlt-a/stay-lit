/// How long the Mac ran with the lid closed while sleep was blocked, and why that stopped.
public struct LidClosedReport: Sendable, Equatable {
    public enum End: Sendable, Equatable {
        case restored(RestoreReason)
        case lidOpened
        /// Sleep was allowed again outside the app, for example from a terminal.
        case sleepAllowedElsewhere
        /// The Mac went to sleep despite the block, for example on an empty battery.
        case macSlept

        /// The run ended as the user planned it, not because the Mac was at risk or slept anyway.
        public var endedAsPlanned: Bool {
            switch self {
            case .restored(.timer), .restored(.claudeFinished), .lidOpened: true
            case .restored(.lowBattery), .restored(.highTemperature), .sleepAllowedElsewhere, .macSlept: false
            }
        }
    }

    public let duration: Duration
    public let end: End

    public init(duration: Duration, end: End) {
        self.duration = duration
        self.end = end
    }
}
