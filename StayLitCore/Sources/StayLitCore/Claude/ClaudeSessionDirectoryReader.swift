import Foundation

/// Reads the registry Claude Code keeps in `~/.claude/sessions`, one `<pid>.json` per session.
/// The format is not documented by Claude Code: a file that is not a session is ignored.
public struct ClaudeSessionDirectoryReader: ClaudeSessionReading {
    private let directory: URL
    private let isProcessAlive: @Sendable (Int32) -> Bool

    public init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/sessions", directoryHint: .isDirectory),
        isProcessAlive: @escaping @Sendable (Int32) -> Bool = Self.processExists
    ) {
        self.directory = directory
        self.isProcessAlive = isProcessAlive
    }

    @concurrent public func sessions() async -> ClaudeSessionCounts {
        // A missing directory is not an error: Claude Code is not installed or never ran.
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return .none }

        // The pid is the file name, so only the files of live processes are read. Only `.json`:
        // the `<pid>.<hash>.key` files next to them are not sessions.
        let decoder = JSONDecoder()
        let activities = files.compactMap { file -> ClaudeActivity? in
            guard file.pathExtension == "json",
                  let pid = Int32(file.deletingPathExtension().lastPathComponent),
                  isProcessAlive(pid)
            else { return nil }
            // A live session we cannot read may be busy: staying awake is the safe side.
            guard let data = try? Data(contentsOf: file),
                  let entry = try? decoder.decode(Entry.self, from: data)
            else { return .working }
            return ClaudeActivity(status: entry.status, bridgeSessionId: entry.bridgeSessionId)
        }
        return ClaudeSessionCounts(activities)
    }

    /// Signal 0 only checks that the process exists. `EPERM` means it exists but belongs to
    /// someone else, so it is alive.
    public static func processExists(_ pid: Int32) -> Bool {
        // `kill` with 0 or a negative pid targets a whole process group: never ask for it.
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private struct Entry: Decodable {
        var status: String?
        var bridgeSessionId: String?

        private enum CodingKeys: String, CodingKey {
            case status, bridgeSessionId
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            // Lenient: an unexpected type here must not hide a readable `status`.
            bridgeSessionId = try? container.decodeIfPresent(String.self, forKey: .bridgeSessionId)
        }
    }
}
