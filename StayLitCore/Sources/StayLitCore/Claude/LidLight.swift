/// What one light on the lid edge stands for, once lit.
public enum LidLight: Sendable, Hashable {
    /// A Claude Code session at work. The only light that breathes.
    case working
    /// A Claude Code session waiting for the user.
    case waiting
    /// Sleep is blocked and no session works or waits.
    case steady

    /// More would not fit the edge, and would not be read at a glance anyway.
    public static let maximumCount = 6

    /// The lights of the edge, left to right: one per working session, then one per waiting
    /// session, or a single steady light. Never empty. The same row serves while sleep is
    /// allowed, unlit, so flipping the switch lights the very lights already there.
    public static func row(for sessions: ClaudeSessionCounts) -> [LidLight] {
        let working = min(sessions.working, maximumCount)
        let waiting = min(sessions.waiting, maximumCount - working)
        let lights = Array(repeating: LidLight.working, count: working)
            + Array(repeating: LidLight.waiting, count: waiting)
        return lights.isEmpty ? [.steady] : lights
    }
}
