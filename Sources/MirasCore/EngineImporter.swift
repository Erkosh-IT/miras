import Foundation

public enum EngineImporter {
    /// Copies a relocatable Wine distribution, then merges Apple's redist/lib into
    /// its lib directory, as specified by compatible Wine distribution maintainers.
    public static func importD3DMetal(engine: URL, redistLib: URL, destination: URL) throws -> URL {
        let fm = FileManager.default
        let resolved = engine.resolvingSymlinksInPath()
        let source = resolved.deletingLastPathComponent().deletingLastPathComponent()
        guard resolved.deletingLastPathComponent().lastPathComponent == "bin",
              fm.fileExists(atPath: source.appendingPathComponent("lib").path) else {
            throw ConfigurationError("Choose an engine with a relocatable bin/ and lib/ layout.")
        }
        for dll in ["d3d11.dll", "d3d12.dll"] {
            guard fm.fileExists(atPath: redistLib.appendingPathComponent("wine/x86_64-windows/\(dll)").path) else {
                throw ConfigurationError("Choose GPTK's redist/lib folder containing wine/x86_64-windows/\(dll). This package layout is not supported.")
            }
        }
        guard let contents = fm.enumerator(at: redistLib, includingPropertiesForKeys: nil),
              contents.compactMap({ $0 as? URL }).contains(where: { $0.lastPathComponent == "D3DMetal.framework" }) else {
            throw ConfigurationError("The selected GPTK library folder has no D3DMetal.framework.")
        }
        guard !fm.fileExists(atPath: destination.path) else { throw ConfigurationError("The managed engine destination already exists.") }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: destination)
        try merge(redistLib, into: destination.appendingPathComponent("lib"))
        return destination.appendingPathComponent("bin/\(resolved.lastPathComponent)")
    }

    private static func merge(_ source: URL, into target: URL) throws {
        let fm = FileManager.default
        if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw ConfigurationError("Refusing to merge through an engine symlink: \(target.path)")
        }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for file in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let destination = target.appendingPathComponent(file.lastPathComponent)
            if values.isSymbolicLink == true {
                // Preserve framework links; never traverse them while merging.
                if fm.fileExists(atPath: destination.path) { throw ConfigurationError("A framework symlink conflicts with the existing engine: \(destination.path)") }
                try fm.copyItem(at: file, to: destination)
            } else if values.isDirectory == true {
                if (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    throw ConfigurationError("Refusing to merge through an engine symlink: \(destination.path)")
                }
                try merge(file, into: destination)
            } else {
                try Data(contentsOf: file).write(to: destination, options: .atomic)
            }
        }
    }
}
