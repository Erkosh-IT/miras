import Foundation

/// File-backed output avoids pipe backpressure and polling while games run.
public enum ProcessRunner {
    public static func start(_ command: WineCommand, log: URL,
                      onExit: @escaping @Sendable (Int32) -> Void = { _ in }) throws -> Process {
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: log)
        let process = Process()
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n[Miras] Starting \(command.executable.lastPathComponent)\n".utf8))
            process.executableURL = command.executable
            process.arguments = command.arguments
            process.environment = command.environment
            process.currentDirectoryURL = command.workingDirectory
            process.standardOutput = handle
            process.standardError = handle
            process.standardInput = FileHandle.nullDevice
            let started = ProcessInfo.processInfo.systemUptime
            process.terminationHandler = { process in
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                let summary = String(format: "\n[Miras] Process exited %d after %.3f seconds\n", process.terminationStatus, elapsed)
                try? handle.write(contentsOf: Data(summary.utf8))
                try? handle.close()
                onExit(process.terminationStatus)
            }
            try process.run()
            return process
        } catch {
            try? handle.close()
            throw ConfigurationError("Could not start \(command.executable.lastPathComponent): \(error.localizedDescription). If x86_64 mode is selected, verify Rosetta 2 and an x86_64-capable engine are available.")
        }
    }

    public static func run(_ command: WineCommand, log: URL) async throws -> Int32 {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            do {
                _ = try start(command, log: log) { code in
                    continuation.resume(returning: code)
                }
            } catch { continuation.resume(throwing: error) }
        }
    }
}
