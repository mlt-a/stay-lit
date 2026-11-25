import Foundation
import Testing
@testable import StayLitCore

/// Writes into a folder of its own and removes it afterwards. Never touches the real `~/.claude`.
private final class SessionsFolder {
    let url: URL

    init(create: Bool = true) throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "StayLitClaudeSessions-\(UUID().uuidString)", directoryHint: .isDirectory)
        if create {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ name: String, _ content: String) throws {
        try content.write(to: url.appending(path: name), atomically: true, encoding: .utf8)
    }

    func session(pid: Int32, status: String?, bridge: String? = nil) throws {
        let fields = field("status", status) + field("bridgeSessionId", bridge)
        try write("\(pid).json", #"{"pid":\#(pid),"sessionId":"abc","kind":"interactive"\#(fields)}"#)
    }

    /// An optional string field of the JSON, with its leading comma. Empty when the value is nil.
    private func field(_ key: String, _ value: String?) -> String {
        value.map { #","\#(key)":"\#($0)""# } ?? ""
    }

    func reader(alive: Set<Int32>) -> ClaudeSessionDirectoryReader {
        ClaudeSessionDirectoryReader(directory: url, isProcessAlive: { alive.contains($0) })
    }
}

struct ClaudeSessionDirectoryReaderTests {
    @Test(arguments: ["busy", nil] as [String?])
    func aBusySessionOrOneWithoutStatusWorks(status: String?) async throws {
        let folder = try SessionsFolder()
        try folder.session(pid: 100, status: status)

        #expect(await folder.reader(alive: [100]).sessions().activity == .working)
    }

    @Test func aSessionUnderRemoteControlWorks() async throws {
        let folder = try SessionsFolder()
        try folder.session(pid: 100, status: "idle", bridge: "session_01abc")

        #expect(await folder.reader(alive: [100]).sessions() == ClaudeSessionCounts(working: 1))
    }

    @Test func aNullOrUnexpectedBridgeIsIgnored() async throws {
        let folder = try SessionsFolder()
        try folder.write("100.json", #"{"status":"idle","bridgeSessionId":null}"#)
        try folder.write("101.json", #"{"status":"idle","bridgeSessionId":42}"#)

        #expect(await folder.reader(alive: [100, 101]).sessions() == .none)
    }

    @Test func theMostActiveLiveSessionWins() async throws {
        let folder = try SessionsFolder()
        try folder.session(pid: 100, status: "idle")
        try folder.session(pid: 101, status: "waiting")

        #expect(await folder.reader(alive: [100, 101]).sessions().activity == .waiting)
    }

    @Test func aDeadProcessIsIgnored() async throws {
        let folder = try SessionsFolder()
        try folder.session(pid: 100, status: "busy")
        try folder.session(pid: 101, status: "idle")

        #expect(await folder.reader(alive: [101]).sessions().activity == .idle)
    }

    @Test func aBrokenJSONFileOfALiveProcessCountsAsWork() async throws {
        let folder = try SessionsFolder()
        try folder.write("100.json", "{not json")
        try folder.session(pid: 102, status: "waiting")

        #expect(await folder.reader(alive: [100, 102]).sessions().activity == .working)
    }

    @Test func aBrokenJSONFileOfADeadProcessIsIgnored() async throws {
        let folder = try SessionsFolder()
        try folder.write("100.json", "{not json")
        try folder.session(pid: 102, status: "waiting")

        #expect(await folder.reader(alive: [102]).sessions().activity == .waiting)
    }

    @Test func aFileNotNamedAfterAPidIsIgnored() async throws {
        let folder = try SessionsFolder()
        try folder.write("latest.json", #"{"status":"busy"}"#)

        #expect(await folder.reader(alive: [0, 100]).sessions().activity == .idle)
    }

    @Test func keyFilesAreIgnored() async throws {
        let folder = try SessionsFolder()
        try folder.write("100.abc123.key", #"{"pid":100,"status":"busy"}"#)

        #expect(await folder.reader(alive: [100]).sessions().activity == .idle)
    }

    @Test func anEmptyFolderIsIdle() async throws {
        let folder = try SessionsFolder()

        #expect(await folder.reader(alive: []).sessions().activity == .idle)
    }

    @Test func aMissingFolderIsIdle() async throws {
        let folder = try SessionsFolder(create: false)

        #expect(await folder.reader(alive: [100]).sessions().activity == .idle)
    }

    @Test func eachLiveSessionIsCountedInItsState() async throws {
        let folder = try SessionsFolder()
        try folder.session(pid: 100, status: "busy")
        try folder.session(pid: 101, status: nil)
        try folder.session(pid: 102, status: "waiting")
        try folder.session(pid: 103, status: "idle")
        try folder.session(pid: 104, status: "idle")
        try folder.session(pid: 105, status: "busy")

        let counts = await folder.reader(alive: [100, 101, 102, 103, 104]).sessions()

        #expect(counts == ClaudeSessionCounts(working: 2, waiting: 1))
    }

    @Test func aMissingOrEmptyFolderHasNoSession() async throws {
        let missing = try SessionsFolder(create: false)
        let empty = try SessionsFolder()

        #expect(await missing.reader(alive: [100]).sessions() == .none)
        #expect(await empty.reader(alive: [100]).sessions() == .none)
    }

    @Test func theRunningTestProcessIsAlive() {
        #expect(ClaudeSessionDirectoryReader.processExists(ProcessInfo.processInfo.processIdentifier))
    }

    @Test(arguments: [Int32(0), -1])
    func aProcessGroupPidIsNeverAlive(pid: Int32) {
        #expect(!ClaudeSessionDirectoryReader.processExists(pid))
    }
}
