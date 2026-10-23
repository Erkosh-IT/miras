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
        let data = try Data(contentsOf: executable, options: .mappedIfSafe)
        guard data.count >= 64, data[0] == 0x4d, data[1] == 0x5a else { throw ConfigurationError("The game is not a valid Windows PE executable.") }
        let offset = (0..<4).reduce(0) { $0 | (Int(data[60 + $1]) << (8 * $1)) }
        guard offset <= data.count - 6, Array(data[offset..<offset+4]) == [0x50, 0x45, 0, 0] else { throw ConfigurationError("The game has an invalid PE header.") }
        let machine = Int(data[offset+4]) | (Int(data[offset+5]) << 8)
        switch machine {
        case 0x8664: return "x64"
        case 0x14c: return "x32"
        default: throw ConfigurationError("This renderer integration supports x86 and x86_64 Windows executables.")
        }
    }
    public static func installDXVK(from package: URL, prefix: URL) throws {
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
        // Validate/read all sources before touching the prefix.
        let payloads = try files.map { try Data(contentsOf: $0.0) }
        for (index, entry) in files.enumerated() {
            if fm.fileExists(atPath: entry.1.path), !fm.fileExists(atPath: entry.2.path) {
                try fm.createDirectory(at: entry.2.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contentsOf: entry.1).write(to: entry.2, options: .atomic)
            }
            try payloads[index].write(to: entry.1, options: .atomic)
        }
    }
}
