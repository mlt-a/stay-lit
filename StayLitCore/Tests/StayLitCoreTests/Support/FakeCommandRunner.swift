import Foundation
@testable import StayLitCore

/// Replays scripted results and records every call. Never starts a process.
final class FakeCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
    }

    private let lock = NSLock()
    private let respond: (Call) -> Result<CommandResult, CommandRunnerError>
    private var recorded: [Call] = []

    /// Answers the calls in order.
    convenience init(_ results: [Result<CommandResult, CommandRunnerError>]) {
        var remaining = results
        self.init { _ in remaining.removeFirst() }
    }

    /// Answers by what was asked, so concurrent calls get a deterministic reply.
    init(respond: @escaping (Call) -> Result<CommandResult, CommandRunnerError>) {
        self.respond = respond
    }

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        let call = Call(executable: executable, arguments: arguments)
        let result = lock.withLock {
            recorded.append(call)
            return respond(call)
        }
        return try result.get()
    }
}
