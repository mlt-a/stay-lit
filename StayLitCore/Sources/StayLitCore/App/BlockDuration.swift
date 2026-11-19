/// How long sleep stays blocked before the app allows it again by itself.
/// `allCases` is the display order.
public enum BlockDuration: Sendable, CaseIterable, Hashable {
    case untilTurnedOff
    case oneHour
    case twoHours
    case fourHours

    /// `nil` when nothing ends the block but the user.
    public var interval: Duration? {
        switch self {
        case .untilTurnedOff: nil
        case .oneHour: .seconds(3600)
        case .twoHours: .seconds(2 * 3600)
        case .fourHours: .seconds(4 * 3600)
        }
    }
}
