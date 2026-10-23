import Foundation

public enum WineError: LocalizedError {
    case missingEngine, missingExecutable(String), invalidInstaller, missingServer
    public var errorDescription: String? {
        switch self {
        case .missingEngine: return "Select an executable Wine engine in Engine settings."
        case .missingExecutable(let path): return "The executable could not be found: \(path)"
        case .invalidInstaller: return "Choose a Windows .exe or .msi installer."
        case .missingServer: return "This engine has no wineserver beside its Wine executable. Stop the game from inside Windows instead."
        }
    }
}

/// Arguments go directly to Process; no command is interpreted by a shell.
public struct WineCommand {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public let workingDirectory: URL?

    public init(engine: URL, prefix: URL, arguments: [String], workingDirectory: URL? = nil,
                inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard FileManager.default.isExecutableFile(atPath: engine.path) else { throw WineError.missingEngine }
        executable = engine
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        var env = inheritedEnvironment
        env["WINEPREFIX"] = prefix.path
        // Keep per-engine DLLs and sibling helper binaries discoverable in a GUI launch.
        env["PATH"] = engine.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        environment = env
    }

    public static func initialize(engine: URL, prefix: URL) throws -> WineCommand {
        try WineCommand(engine: engine, prefix: prefix, arguments: ["wineboot", "--init"])
    }
    public static func launch(engine: URL, prefix: URL, game: Game, configuration: RuntimeConfiguration = RuntimeConfiguration()) throws -> WineCommand {
        guard FileManager.default.fileExists(atPath: game.executable) else { throw WineError.missingExecutable(game.executable) }
        var command = try WineCommand(engine: engine, prefix: prefix, arguments: [game.executable] + game.arguments,
                               workingDirectory: URL(fileURLWithPath: game.executable).deletingLastPathComponent())
        let options = game.options
        // Retain error diagnostics while avoiding Wine's routine fixme/trace traffic.
        command.environment["WINEDEBUG"] = options.diagnostics ? "-all,err+all,warn+all,fixme+all" : "-all,err+all"
        let customOverrides = try options.mods.overrides()
        let extensionName = URL(fileURLWithPath: game.executable).pathExtension.lowercased()
        let isBatch = ["bat", "cmd"].contains(extensionName)
        guard isBatch || extensionName == "exe" else { throw ConfigurationError("Choose an .exe, .bat, or .cmd launcher.") }
        if isBatch {
            let windowsPath = "Z:" + game.executable.replacingOccurrences(of: "/", with: "\\")
            let tokens = [windowsPath] + game.arguments
            // cmd.exe parses these a second time. Reject expansion/control syntax
            // instead of claiming that Process argument boundaries protect it.
            let forbidden = CharacterSet(charactersIn: "\"&|<>^%!\r\n\u{0}")
            guard tokens.allSatisfy({ $0.rangeOfCharacter(from: forbidden) == nil }) else {
                throw ConfigurationError("Batch paths and arguments cannot contain quotes, shell operators, or expansion characters. Use the mod's .exe launcher for those arguments.")
            }
            let line = tokens.map { "\"\($0)\"" }.joined(separator: " ")
            command.arguments = ["cmd", "/d", "/s", "/c", "\"" + line + "\""]
        }
        func targetArchitecture() throws -> String {
            if isBatch {
                guard ["x64", "x32"].contains(options.mods.batchArchitecture) else { throw ConfigurationError("Select the batch launcher's game architecture.") }
                return options.mods.batchArchitecture
            }
            return try GraphicsRuntime.architecture(of: URL(fileURLWithPath: game.executable))
        }
        guard options.synchronization != .esync || configuration.supportsESync else { throw ConfigurationError("This engine has not been configured for ESync.") }
        guard options.synchronization != .msync || configuration.supportsMSync else { throw ConfigurationError("This engine has not been configured for MSync.") }
        command.environment["WINEESYNC"] = options.synchronization == .esync ? "1" : "0"
        command.environment["WINEMSYNC"] = options.synchronization == .msync ? "1" : "0"
        command.environment["WINEFSYNC"] = "0"
        let managed = Set(["d3d9", "d3d10", "d3d10_1", "d3d10core", "d3d11", "dxgi", "d3d12"])
        let retainedOverrides = (command.environment["WINEDLLOVERRIDES"] ?? "").split(separator: ";").compactMap { entry -> String? in
            let pair = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            let names = pair[0].split(separator: ",").filter {
                let name = $0.trimmingCharacters(in: .whitespaces).lowercased()
                return !managed.contains(name) && customOverrides[name] == nil
            }
            return names.isEmpty ? nil : names.joined(separator: ",") + "=" + String(pair[1])
        }
        let builtins = "d3d9,d3d10,d3d10_1,d3d10core,d3d11,dxgi,d3d12=b"
        switch options.graphics {
        case .wine: command.environment["WINEDLLOVERRIDES"] = builtins
        case .d3dMetal:
            guard configuration.d3dMetalReady else { throw ConfigurationError("Configure a GPTK-compatible engine with Apple's D3DMetal components in Engine settings first.") }
            guard try targetArchitecture() == "x64" else { throw ConfigurationError("D3DMetal requires a 64-bit Windows executable.") }
            command.environment["WINEDLLOVERRIDES"] = builtins
        case .dxvk:
            guard !configuration.dxvkPath.isEmpty else { throw ConfigurationError("Choose a macOS DXVK package in Engine settings first.") }
            let package = URL(fileURLWithPath: configuration.dxvkPath)
            let architecture = try targetArchitecture()
            let names = ["d3d9", "d3d10", "d3d10_1", "d3d10core", "d3d11", "dxgi"]
            let native = names.filter { FileManager.default.fileExists(atPath: package.appendingPathComponent("\(architecture)/\($0).dll").path) }
            guard native.contains("d3d11"), native.contains("dxgi") else { throw ConfigurationError("The DXVK package is missing \(architecture)/d3d11.dll or \(architecture)/dxgi.dll.") }
            command.environment["WINEDLLOVERRIDES"] = "d3d12=b;" + names.map { "\($0)=\(native.contains($0) ? "n" : "b")" }.joined(separator: ";")
            command.environment["MVK_CONFIG_RESUME_LOST_DEVICE"] = "1"
        }
        if !retainedOverrides.isEmpty {
            command.environment["WINEDLLOVERRIDES"]! += ";" + retainedOverrides.joined(separator: ";")
        }
        if !customOverrides.isEmpty {
            command.environment["WINEDLLOVERRIDES"]! += ";" + customOverrides.keys.sorted().map { "\($0)=\(customOverrides[$0]!)" }.joined(separator: ";")
        }
        if options.rosetta {
            command.arguments = ["-x86_64", engine.path] + command.arguments
            command.executable = URL(fileURLWithPath: "/usr/bin/arch")
        }
        return command
    }

    public static func steam(engine: URL, prefix: URL, game: Game, configuration: RuntimeConfiguration) throws -> WineCommand {
        let selected = game.options.mods.steamExecutable
        let steam = selected.isEmpty ? prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe") : URL(fileURLWithPath: selected)
        guard steam.resolvingSymlinksInPath().path.hasPrefix(prefix.resolvingSymlinksInPath().path + "/"),
              steam.lastPathComponent.lowercased() == "steam.exe", FileManager.default.fileExists(atPath: steam.path) else {
            throw ConfigurationError("Select steam.exe installed inside this game's bottle, or install Steam in its default location there.")
        }
        let uri = try game.options.mods.validatedSteamURL()
        let gameCommand = try launch(engine: engine, prefix: prefix, game: game, configuration: configuration)
        var command = try WineCommand(engine: engine, prefix: prefix, arguments: [steam.path] + (uri.map { [$0] } ?? ["-silent"]), workingDirectory: steam.deletingLastPathComponent())
        for key in ["WINEESYNC", "WINEMSYNC", "WINEFSYNC", "WINEDEBUG"] { command.environment[key] = gameCommand.environment[key] }
        // The game's mod DLLs must not be injected into the Steam client.
        command.environment.removeValue(forKey: "WINEDLLOVERRIDES")
        if game.options.rosetta {
            command.executable = URL(fileURLWithPath: "/usr/bin/arch")
            command.arguments = ["-x86_64", engine.path] + command.arguments
        }
        return command
    }

    public static func dependencies(engine: URL, prefix: URL, tool: URL, verbs: [WindowsDependency]) throws -> WineCommand {
        guard !verbs.isEmpty else { throw ConfigurationError("Select at least one dependency.") }
        var command = try WineCommand(engine: engine, prefix: prefix, arguments: ["-q"] + verbs.map(\.rawValue))
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { throw ConfigurationError("Choose an executable Winetricks script in Engine settings.") }
        command.executable = tool
        command.environment["WINE"] = engine.path
        command.environment["WINESERVER"] = engine.deletingLastPathComponent().appendingPathComponent("wineserver").path
        return command
    }

    public static func wait(engine: URL, prefix: URL) throws -> WineCommand {
        let server = engine.deletingLastPathComponent().appendingPathComponent("wineserver")
        guard FileManager.default.isExecutableFile(atPath: server.path) else { throw WineError.missingServer }
        return try WineCommand(engine: server, prefix: prefix, arguments: ["-w"])
    }
    public static func install(engine: URL, prefix: URL, installer: URL) throws -> WineCommand {
        guard FileManager.default.fileExists(atPath: installer.path) else { throw WineError.missingExecutable(installer.path) }
        let ext = installer.pathExtension.lowercased()
        guard ["exe", "msi"].contains(ext) else { throw WineError.invalidInstaller }
        return try WineCommand(engine: engine, prefix: prefix,
                               arguments: ext == "msi" ? ["msiexec", "/i", installer.path] : [installer.path],
                               workingDirectory: installer.deletingLastPathComponent())
    }
    public static func stop(engine: URL, prefix: URL) throws -> WineCommand {
        let server = engine.deletingLastPathComponent().appendingPathComponent("wineserver")
        guard FileManager.default.isExecutableFile(atPath: server.path) else { throw WineError.missingServer }
        return try WineCommand(engine: server, prefix: prefix, arguments: ["-k"])
    }
}
