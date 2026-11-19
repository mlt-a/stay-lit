/// Absolute paths of every executable the package runs. Nothing is looked up in `PATH`.
enum Executables {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"
    static let visudo = "/usr/sbin/visudo"
    static let osascript = "/usr/bin/osascript"

    // Only used inside the root script.
    static let printf = "/usr/bin/printf"
    static let chown = "/usr/sbin/chown"
    static let chmod = "/bin/chmod"
    static let mv = "/bin/mv"
    static let rm = "/bin/rm"
}
