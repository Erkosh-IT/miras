import Foundation
import MirasCore

/// Log to a file rather than pipes so verbose games cannot block on a full pipe.
enum Runner {
    static func run(_ command: WineCommand, log: URL) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: log.path) {
                    FileManager.default.createFile(atPath: log.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: log)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("\n[Miras] Starting \(command.executable.lastPathComponent)\n".utf8))
                let process = Process()
                process.executableURL = command.executable
                process.arguments = command.arguments
                process.environment = command.environment
                process.currentDirectoryURL = command.workingDirectory
                process.standardOutput = handle
                process.standardError = handle
                process.standardInput = FileHandle.nullDevice
                process.terminationHandler = { process in
                    try? handle.close()
                    continuation.resume(returning: process.terminationStatus)
                }
                do { try process.run() }
                catch {
                    try? handle.close()
                    continuation.resume(throwing: ConfigurationError("Could not start \(command.executable.lastPathComponent): \(error.localizedDescription). If x86_64 mode is selected, verify Rosetta 2 is installed and the Wine engine supports x86_64."))
                }
            } catch { continuation.resume(throwing: error) }
        }
    }
}
