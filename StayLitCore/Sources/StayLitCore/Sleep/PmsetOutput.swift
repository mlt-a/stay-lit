/// Reads the `pmset -g` report.
public enum PmsetOutput {
    /// Whether `SleepDisabled` is set to 1.
    ///
    /// `pmset -g` only prints the `SleepDisabled` line while the setting is on,
    /// so a missing line means sleep is allowed.
    public static func isSleepDisabled(in output: String) -> Bool {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0] == "SleepDisabled" {
                return fields[1] == "1"
            }
        }
        return false
    }
}
