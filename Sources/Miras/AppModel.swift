import AppKit
import SwiftUI
import MirasCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var library = Library()
    @Published private(set) var busy: [UUID: String] = [:]
    @Published private(set) var logs: [UUID: URL] = [:]
    @Published var selection: UUID?
    @Published var errorMessage: String?
    @Published var status = "Choose an engine to get started."
    @Published private(set) var storageReady = false
    let store: LibraryStore
    private var workflowTasks: [UUID: Task<Void, Never>] = [:]
    @Published private(set) var steamSessions: [UUID: LaunchSettings] = [:]
    private var steamProcesses: [UUID: Process] = [:]
    private var steamSessionIDs: [UUID: UUID] = [:]
    @Published private(set) var stopping: Set<UUID> = []
    var runtimeLocked: Bool { !busy.isEmpty || !steamSessions.isEmpty || !stopping.isEmpty }

    var selectedBottle: Bottle? { library.bottles.first { $0.id == selection } }
    var engineReady: Bool { FileManager.default.isExecutableFile(atPath: library.enginePath) }
    var engine: URL { URL(fileURLWithPath: library.enginePath) }
    var canRun: Bool { storageReady && engineReady }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = LibraryStore(root: support.appendingPathComponent("Miras", isDirectory: true))
        do {
            library = try store.load()
            storageReady = true
            selection = library.bottles.first?.id
            status = engineReady ? "Ready to play." : "Choose an engine to get started."
        } catch {
            errorMessage = "The library could not be read. Your existing data has been preserved. Open the data folder to repair library.json, then restart Miras.\n\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func commit(_ update: (inout Library) -> Void) -> Bool {
        guard storageReady else { return false }
        var next = library
        update(&next)
        do {
            try store.save(next)
            library = next
            return true
        } catch { errorMessage = "Could not save your library: \(error.localizedDescription)"; return false }
    }

    func chooseEngine() {
        guard !runtimeLocked else { return }
        let panel = NSOpenPanel()
        panel.title = "Select the wine or wine64 executable"
        panel.message = "Select the Wine binary inside your engine's bin directory. Use Command–Shift–G to enter a path inside an app bundle."
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path), ["wine", "wine64"].contains(url.lastPathComponent) else {
            errorMessage = "Select a runnable binary named wine or wine64, not the engine's .app bundle."
            return
        }
        if commit({ $0.enginePath = url.path; $0.runtime = nil }) { status = "Engine selected. Create a bottle to install a game." }
    }

    func discoverEngine() {
        guard !runtimeLocked else { return }
        let candidates = [
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine",
            "/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine",
            "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine",
            "/opt/homebrew/bin/wine", "/usr/local/bin/wine"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            if commit({ $0.enginePath = path; $0.runtime = nil }) { status = "Wine engine found." }
        } else { errorMessage = "No Wine engine was found in the usual locations. Install a macOS-compatible Wine engine from its publisher, then choose its wine binary." }
    }

    func createBottle(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, canRun else { return }
        let bottle = Bottle(name: name)
        perform(bottle: bottle, title: "Creating bottle") { [self] in
            let prefix = store.prefix(for: bottle)
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
            return try WineCommand.initialize(engine: engine, prefix: prefix)
        } onSuccess: { [self] in
            if commit({ $0.bottles.append(bottle) }) { selection = bottle.id }
        }
    }

    func install(in bottle: Bottle) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows installer (.exe or .msi)"
        guard panel.runModal() == .OK, let installer = panel.url else { return }
        perform(bottle: bottle, title: "Running installer") { [self] in
            try WineCommand.install(engine: engine, prefix: store.prefix(for: bottle), installer: installer)
        }
    }

    func installNew() {
        guard canRun else { return }
        let panel = NSOpenPanel()
        panel.title = "Install a Windows game in a new bottle"
        guard panel.runModal() == .OK, let installer = panel.url else { return }
        let bottle = Bottle(name: installer.deletingPathExtension().lastPathComponent)
        let prefix = store.prefix(for: bottle)
        let selectedEngine = engine
        workflow(bottle: bottle, title: "Installing in a new bottle") { [self] log in
            // Validate the installer before creating any data.
            let install = try WineCommand.install(engine: selectedEngine, prefix: prefix, installer: installer)
            let wait = try WineCommand.wait(engine: selectedEngine, prefix: prefix)
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
            try await checkedRun(WineCommand.initialize(engine: selectedEngine, prefix: prefix), log: log)
            try await checkedRun(wait, log: log)
            guard commit({ $0.bottles.append(bottle) }) else { throw ConfigurationError("The new bottle could not be saved.") }
            selection = bottle.id
            try await checkedRun(install, log: log)
            try await checkedRun(wait, log: log)
        }
    }

    func saveConfiguration(_ configuration: RuntimeConfiguration) {
        guard !runtimeLocked else { return }
        commit { $0.configuration = configuration }
    }

    func importD3DMetal() {
        guard canRun, !runtimeLocked else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Apple's GPTK redist/lib folder"
        panel.message = "Miras will copy the selected Wine engine and merge these libraries into that private copy. Use a Wine build compatible with this GPTK release."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let libraries = panel.url else { return }
        let original = engine
        let id = UUID()
        let destination = store.root.appendingPathComponent("Engines/\(id)")
        busy[id] = "Importing D3DMetal"
        status = "Copying engine and importing D3DMetal…"
        Task {
            defer { busy.removeValue(forKey: id) }
            do {
                let imported = try await Task.detached {
                    try EngineImporter.importD3DMetal(engine: original, redistLib: libraries, destination: destination)
                }.value
                if commit({ $0.enginePath = imported.path; $0.configuration.d3dMetalReady = true }) {
                    status = "D3DMetal imported. Select it in Game settings."
                }
            } catch { errorMessage = "\(error.localizedDescription)\n\nThe original engine is unchanged. Any partial copy is at \(destination.path)." }
        }
    }

    func addGame(to bottle: Bottle) {
        let panel = NSOpenPanel()
        panel.title = "Add a game or mod launcher (.exe, .bat, .cmd)"
        panel.message = "Browse this bottle's drive_c to find the installed game's executable."
        panel.directoryURL = store.prefix(for: bottle).appendingPathComponent("drive_c")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard ["exe", "bat", "cmd"].contains(url.pathExtension.lowercased()) else {
            errorMessage = "Choose a Windows .exe, .bat, or .cmd launcher."; return
        }
        let game = Game(bottleID: bottle.id, name: url.deletingPathExtension().lastPathComponent, executable: url.path)
        commit { $0.games.append(game) }
    }

    func updateGame(_ game: Game) {
        commit { library in
            if let index = library.games.firstIndex(where: { $0.id == game.id }) { library.games[index] = game }
        }
    }

    func removeGame(_ game: Game) { commit { $0.games.removeAll { $0.id == game.id } } }

    private func sessionProfile(_ game: Game) -> LaunchSettings {
        var options = game.options
        var mods = ModSettings()
        mods.steamExecutable = options.mods.steamExecutable
        options.modSettings = mods
        options.diagnosticsEnabled = nil
        options.dependencies = Array(Set(options.dependencies)).sorted { $0.rawValue < $1.rawValue }
        return options
    }

    func startSteam(for game: Game, in bottle: Bottle) {
        let selectedEngine = engine
        let configuration = library.configuration
        let prefix = store.prefix(for: bottle)
        workflow(bottle: bottle, title: "Starting Steam") { [self] log in
            let command = try WineCommand.steam(engine: selectedEngine, prefix: prefix, game: game, configuration: configuration)
            let profile = sessionProfile(game)
            if let existing = steamSessions[bottle.id] {
                guard existing == profile else { throw ConfigurationError("Stop this bottle before changing graphics, synchronization, dependencies, or Steam installation.") }
            } else {
                let wait = try WineCommand.wait(engine: selectedEngine, prefix: prefix)
                status = "Preparing Steam session; waiting for previous bottle programs to exit…"
                try await checkedRun(wait, log: log)
                if !game.options.dependencies.isEmpty {
                    try await checkedRun(WineCommand.dependencies(engine: selectedEngine, prefix: prefix,
                        tool: URL(fileURLWithPath: configuration.winetricksPath), verbs: game.options.dependencies), log: log)
                    try await checkedRun(wait, log: log)
                }
                if game.options.graphics == .dxvk {
                    try await prepareDXVK(configuration: configuration, prefix: prefix, log: log)
                }
            }
            try Task.checkCancellation()
            if steamSessionIDs[bottle.id] == nil {
                let sessionID = UUID()
                let process = try Runner.start(command, log: log) { [weak self] code in
                    Task { @MainActor in
                        await self?.finishSteamSession(bottle: bottle, sessionID: sessionID, engine: selectedEngine, log: log, exitCode: code)
                    }
                }
                steamSessionIDs[bottle.id] = sessionID
                steamProcesses[bottle.id] = process
            } else {
                // A URL request uses Steam's IPC; do not add another session watcher.
                _ = try Runner.start(command, log: log)
            }
            steamSessions[bottle.id] = profile
        }
    }

    func launch(_ game: Game, in bottle: Bottle) {
        let selectedEngine = engine
        let configuration = library.configuration
        let prefix = store.prefix(for: bottle)
        workflow(bottle: bottle, title: "Running \(game.name)") { [self] log in
            let launch = try WineCommand.launch(engine: selectedEngine, prefix: prefix, game: game, configuration: configuration)
            let wait = try WineCommand.wait(engine: selectedEngine, prefix: prefix)
            let session = steamSessions[bottle.id]
            if let session, session != sessionProfile(game) {
                throw ConfigurationError("Stop this bottle's Steam session before changing graphics, synchronization, dependencies, or Steam installation.")
            }
            if session == nil {
                var dependencies: WineCommand?
                if !game.options.dependencies.isEmpty {
                    dependencies = try WineCommand.dependencies(engine: selectedEngine, prefix: prefix,
                        tool: URL(fileURLWithPath: configuration.winetricksPath), verbs: game.options.dependencies)
                }
                status = "Waiting for this bottle's previous programs to close…"
                try await checkedRun(wait, log: log)
                if let dependencies {
                    status = "Installing selected dependencies for \(game.name)…"
                    try await checkedRun(dependencies, log: log)
                    try await checkedRun(wait, log: log)
                }
                if game.options.graphics == .dxvk {
                    try await prepareDXVK(configuration: configuration, prefix: prefix, log: log)
                }
            }
            status = "Running \(game.name)…"
            try Task.checkCancellation()
            let code = try await Runner.run(launch, log: log)
            // Keep the bottle locked even when Steam or another launcher detaches.
            if session == nil { try await checkedRun(wait, log: log) }
            guard code == 0 else { throw ConfigurationError("Game process exited with code \(code).") }
        }
    }

    private func checkedRun(_ command: WineCommand, log: URL) async throws {
        try Task.checkCancellation()
        let code = try await Runner.run(command, log: log)
        try Task.checkCancellation()
        guard code == 0 else { throw ConfigurationError("\(command.executable.lastPathComponent) exited with code \(code).") }
    }

    private func prepareDXVK(configuration: RuntimeConfiguration, prefix: URL, log: URL) async throws {
        status = "Checking graphics libraries…"
        let report = try await RuntimePreparation.installDXVK(from: URL(fileURLWithPath: configuration.dxvkPath), prefix: prefix)
        try Task.checkCancellation()
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("[Miras] DXVK: \(report.filesCopied) copied, \(report.filesSkipped) unchanged, \(report.bytesCopied) bytes written\n".utf8))
    }

    private func finishSteamSession(bottle: Bottle, sessionID: UUID, engine: URL, log: URL, exitCode: Int32) async {
        guard steamSessionIDs[bottle.id] == sessionID else { return }
        do {
            // Steam can detach from its loader; unlock only after the prefix exits.
            // wineserver waits off-thread, without polling.
            let code = try await Runner.run(WineCommand.wait(engine: engine, prefix: store.prefix(for: bottle)), log: log)
            guard code == 0, steamSessionIDs[bottle.id] == sessionID else { return }
            steamSessions.removeValue(forKey: bottle.id)
            steamProcesses.removeValue(forKey: bottle.id)
            steamSessionIDs.removeValue(forKey: bottle.id)
            if exitCode != 0 { errorMessage = "Steam exited with code \(exitCode). See \(log.path)." }
        } catch {
            // Keep the session locked if its termination cannot be confirmed.
            if steamSessionIDs[bottle.id] == sessionID { errorMessage = error.localizedDescription }
        }
    }

    private func workflow(bottle: Bottle, title: String, operation: @escaping @MainActor (URL) async throws -> Void) {
        guard canRun, busy[bottle.id] == nil, !stopping.contains(bottle.id) else { return }
        busy[bottle.id] = title
        let log = newLog(bottle: bottle, title: title)
        workflowTasks[bottle.id] = Task {
            defer { busy.removeValue(forKey: bottle.id); workflowTasks.removeValue(forKey: bottle.id) }
            do { try await operation(log); status = "\(title) finished." }
            catch is CancellationError { status = "\(title) stopped." }
            catch { status = "\(title) failed."; errorMessage = "\(error.localizedDescription)\n\nLog: \(log.path)" }
        }
    }

    func configure(_ bottle: Bottle) {
        perform(bottle: bottle, title: "Windows configuration") { [self] in
            try WineCommand(engine: engine, prefix: store.prefix(for: bottle), arguments: ["winecfg"])
        }
    }

    func stop(_ bottle: Bottle) {
        guard canRun, !stopping.contains(bottle.id) else { return }
        let log = newLog(bottle: bottle, title: "Stop")
        do {
            let command = try WineCommand.stop(engine: engine, prefix: store.prefix(for: bottle))
            stopping.insert(bottle.id)
            workflowTasks[bottle.id]?.cancel()
            Task {
                defer { stopping.remove(bottle.id) }
                do {
                    let code = try await Runner.run(command, log: log)
                    if code != 0 { errorMessage = "Wine could not stop this bottle (exit \(code)). See \(log.path)." }
                    else {
                        try await checkedRun(WineCommand.wait(engine: engine, prefix: store.prefix(for: bottle)), log: log)
                        steamSessions.removeValue(forKey: bottle.id)
                        steamProcesses.removeValue(forKey: bottle.id)
                        steamSessionIDs.removeValue(forKey: bottle.id)
                        status = "Stopped programs in \(bottle.name)."
                    }
                } catch { errorMessage = error.localizedDescription }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func reveal(_ bottle: Bottle) { NSWorkspace.shared.open(store.prefix(for: bottle)) }
    func revealData() {
        do {
            try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
            NSWorkspace.shared.open(store.root)
        } catch { errorMessage = error.localizedDescription }
    }

    private func newLog(bottle: Bottle, title: String) -> URL {
        let log = store.root.appendingPathComponent("Logs").appendingPathComponent("\(bottle.id)-\(UUID()).log")
        logs[bottle.id] = log
        return log
    }

    private func perform(bottle: Bottle, title: String, command: () throws -> WineCommand,
                         onSuccess: @escaping @MainActor () -> Void = {}) {
        guard canRun, busy[bottle.id] == nil, !stopping.contains(bottle.id) else { return }
        guard steamSessions[bottle.id] == nil else { errorMessage = "Stop this bottle's Steam session before running installers or changing Windows configuration."; return }
        do {
            let command = try command()
            let wait = try WineCommand.wait(engine: engine, prefix: store.prefix(for: bottle))
            let log = newLog(bottle: bottle, title: title)
            busy[bottle.id] = title
            status = "\(title)…"
            Task {
                defer { busy.removeValue(forKey: bottle.id) }
                do {
                    let code = try await Runner.run(command, log: log)
                    try await checkedRun(wait, log: log)
                    if code == 0 { status = "\(title) finished."; onSuccess() }
                    else {
                        status = "\(title) exited with code \(code)."
                        errorMessage = "\(title) exited with code \(code).\n\nLog: \(log.path)\n\nFor a failed bottle creation, the unfinished prefix is kept in the data folder for troubleshooting."
                    }
                } catch { errorMessage = error.localizedDescription; status = "\(title) failed." }
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
