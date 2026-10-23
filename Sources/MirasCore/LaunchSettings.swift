import Foundation

public enum GraphicsBackend: String, Codable, CaseIterable {
    case wine = "Engine built-ins", d3dMetal = "D3DMetal (GPTK)", dxvk = "DXVK / MoltenVK"
}
public enum Synchronization: String, Codable, CaseIterable {
    case disabled = "Off", esync = "ESync", msync = "MSync"
}
public enum WindowsDependency: String, Codable, CaseIterable {
    case vcrun2022, dotnet48, d3dcompiler_47
}
public struct LaunchSettings: Codable, Equatable {
    public var graphics: GraphicsBackend = .wine
    public var synchronization: Synchronization = .disabled
    public var rosetta = false
    public var dependencies: [WindowsDependency] = []
    public var modSettings: ModSettings?
    public var diagnosticsEnabled: Bool?
    public var diagnostics: Bool {
        get { diagnosticsEnabled ?? false }
        set { diagnosticsEnabled = newValue }
    }
    public var mods: ModSettings {
        get { modSettings ?? ModSettings() }
        set { modSettings = newValue }
    }
    public init() {}
}
public struct RuntimeConfiguration: Codable, Equatable {
    public var d3dMetalReady = false
    public var supportsESync = false
    public var supportsMSync = false
    public var dxvkPath = ""
    public var winetricksPath = ""
    public init() {}
}
public struct ConfigurationError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Installs native DXVK DLLs while retaining originals. Built-in overrides bypass
/// these DLLs for other backends; the engine itself is never modified here.
public enum GraphicsRuntime {
    public static func architecture(of executable: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: executable)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 64) ?? Data()
        guard data.count >= 64, data[0] == 0x4d, data[1] == 0x5a else { throw ConfigurationError("The game is not a valid Windows PE executable.") }
        let offset = (0..<4).reduce(0) { $0 | (Int(data[60 + $1]) << (8 * $1)) }
        guard offset >= 64 else { throw ConfigurationError("The game has an invalid PE header offset.") }
        try handle.seek(toOffset: UInt64(offset))
        let header = try handle.read(upToCount: 6) ?? Data()
        guard header.count == 6, Array(header.prefix(4)) == [0x50, 0x45, 0, 0] else { throw ConfigurationError("The game has an invalid PE header.") }
        let machine = Int(header[4]) | (Int(header[5]) << 8)
        switch machine {
        case 0x8664: return "x64"
        case 0x14c: return "x32"
        default: throw ConfigurationError("This renderer integration supports x86 and x86_64 Windows executables.")
        }
    }
    @discardableResult
    public static func installDXVK(from package: URL, prefix: URL) throws -> InstallationReport {
        let fm = FileManager.default
        let names = ["d3d9", "d3d10", "d3d10_1", "d3d10core", "d3d11", "dxgi"]
        var files: [(URL, URL, URL)] = []
        for (arch, directory) in [("x64", "system32"), ("x32", "syswow64")] {
            let source = package.appendingPathComponent(arch)
            guard fm.fileExists(atPath: source.path) else {
                if arch == "x64" { throw ConfigurationError("DXVK package must contain an x64 directory.") }
                continue
            }
            for required in ["d3d11.dll", "dxgi.dll"] {
                guard fm.fileExists(atPath: source.appendingPathComponent(required).path) else {
                    throw ConfigurationError("DXVK \(arch) is missing \(required).")
                }
            }
            let target = prefix.appendingPathComponent("drive_c/windows/\(directory)")
            guard fm.fileExists(atPath: target.path) else { throw ConfigurationError("Initialize this 64-bit bottle before installing DXVK.") }
            for name in names {
                let file = source.appendingPathComponent(name + ".dll")
                if fm.fileExists(atPath: file.path) {
                    files.append((file, target.appendingPathComponent(name + ".dll"),
                                  prefix.appendingPathComponent(".miras-dll-backups/\(directory)/\(name).dll")))
                }
            }
        }
        // Validate readability without loading the entire DLL set into memory.
        for entry in files {
            let handle = try FileHandle(forReadingFrom: entry.0)
            try handle.close()
        }
        var report = InstallationReport()
        for entry in files {
            try Task.checkCancellation()
            if try identical(entry.0, entry.1) {
                report.filesSkipped += 1
                continue
            }
            if fm.fileExists(atPath: entry.1.path), !fm.fileExists(atPath: entry.2.path) {
                try fm.createDirectory(at: entry.2.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contentsOf: entry.1, options: .mappedIfSafe).write(to: entry.2, options: .atomic)
            }
            // At most one replacement payload is held at a time.
            let payload = try Data(contentsOf: entry.0, options: .mappedIfSafe)
            try Task.checkCancellation()
            try payload.write(to: entry.1, options: .atomic)
            report.filesCopied += 1
            report.bytesCopied += payload.count
        }
        return report
    }

    private static func identical(_ source: URL, _ destination: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: destination.path) else { return false }
        let left = try FileHandle(forReadingFrom: source)
        defer { try? left.close() }
        let right = try FileHandle(forReadingFrom: destination)
        defer { try? right.close() }
        guard try left.seekToEnd() == right.seekToEnd() else { return false }
        try left.seek(toOffset: 0); try right.seek(toOffset: 0)
        while true {
            try Task.checkCancellation()
            let a = try left.read(upToCount: 65_536) ?? Data()
            let b = try right.read(upToCount: 65_536) ?? Data()
            guard a == b else { return false }
            if a.isEmpty { return true }
        }
    }
}

public struct InstallationReport: Equatable {
    public var filesCopied = 0
    public var filesSkipped = 0
    public var bytesCopied = 0
}

public enum RuntimePreparation {
    // A nonisolated async function runs on the generic executor in Swift 5.9.
    // It inherits task cancellation, unlike an unstructured detached task.
    public static func installDXVK(from package: URL, prefix: URL) async throws -> InstallationReport {
        try Task.checkCancellation()
        return try GraphicsRuntime.installDXVK(from: package, prefix: prefix)
    }
}
