import Foundation

/// What a finished command left behind.
public struct CommandResult: Sendable, Equatable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var isSuccess: Bool { exitCode == 0 }

    var trimmedStandardError: String {
        standardError.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Throws `SleepControlError.commandFailed` for a non-zero exit code.
    func requireSuccess(executable: String, arguments: [String]) throws {
        guard !isSuccess else { return }
        throw SleepControlError.commandFailed(
            command: ([executable] + arguments).joined(separator: " "),
            exitCode: exitCode,
            message: trimmedStandardError
        )
    }
}

/// Runs an executable and reports how it ended.
///
/// Implementations never go through a shell: the executable is an absolute path and the
/// arguments are passed as they are, so no argument is ever parsed or expanded.
/// A command that ends with a non-zero exit code is a result, not an error.
/// Only a command that cannot be started throws.
public protocol CommandRunning: Sendable {
    /// Runs the command without blocking the caller's executor.
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult
}

public enum CommandRunnerError: Error, Equatable, Sendable {
    /// The process could not be started (missing executable, not executable, ...).
    case launchFailed(executable: String, reason: String)
}

/// Runs commands as child processes with `Process`.
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        // A dispatch thread, not the cooperative pool: the process can live for minutes
        // (the password dialog) and would pin one of the pool's few threads.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try runSynchronously(executable, arguments: arguments) })
            }
        }
    }

    private func runSynchronously(_ executable: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.launchFailed(
                executable: executable,
                reason: error.localizedDescription
            )
        }

        // Drain both pipes at the same time: a command that fills one pipe while we
        // wait on the other would block forever.
        let errorData = DataBox()
        let drained = DispatchGroup()
        let errorHandle = errorPipe.fileHandleForReading
        DispatchQueue.global().async(group: drained) {
            errorData.value = errorHandle.readDataToEndOfFile()
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        drained.wait()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData.value, as: UTF8.self)
        )
    }
}

/// Hands the stderr bytes from the draining thread back to the caller.
/// Safe because the caller only reads `value` after `DispatchGroup.wait()` returns,
/// which orders it after the write.
private final class DataBox: @unchecked Sendable {
    var value = Data()
}
