import Foundation
import XCTest
@testable import MirasCore

final class RuntimeTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    @discardableResult
    func file(_ path: String, data: Data = Data("original".utf8), executable: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        return url
    }
    func pe(_ arch: String) throws -> URL {
        var data = Data(repeating: 0, count: 128)
        data[0] = 0x4d; data[1] = 0x5a; data[60] = 64
        data[64] = 0x50; data[65] = 0x45
        data[68] = arch == "x64" ? 0x64 : 0x4c
        data[69] = arch == "x64" ? 0x86 : 0x01
        return try file("\(arch).exe", data: data)
    }
    func testOldLibraryMigratesWithoutNewSettings() throws {
        let json = """
        {"enginePath":"/wine","bottles":[],"games":[{"id":"00000000-0000-0000-0000-000000000001","bottleID":"00000000-0000-0000-0000-000000000002","name":"Old","executable":"/old.exe","arguments":[]}]}
        """
        let library = try JSONDecoder().decode(Library.self, from: Data(json.utf8))
        XCTAssertEqual(library.games[0].options, LaunchSettings())
        XCTAssertEqual(library.configuration, RuntimeConfiguration())
    }
    func testExistingLaunchSettingsDecodeWithoutMods() throws {
        let json = """
        {"graphics":"Engine built-ins","synchronization":"Off","rosetta":false,"dependencies":[]}
        """
        let options = try JSONDecoder().decode(LaunchSettings.self, from: Data(json.utf8))
        XCTAssertEqual(options.mods, ModSettings())
    }
    func testModOverridesAreValidatedAndGraphicsStayManaged() throws {
        var settings = ModSettings()
        settings.dllOverrides = "winmm=n\nsteam_api64=n,b\nonlinefix64=n\nsteamoverlay64=n\ndnet=n"
        XCTAssertEqual(try settings.overrides()["winmm"], "n")
        settings.dllOverrides = "dxgi=n"
        XCTAssertThrowsError(try settings.overrides())
        settings.dllOverrides = "winmm=n;other=n"
        XCTAssertThrowsError(try settings.overrides())
        settings.dllOverrides = "../winmm=n"
        XCTAssertThrowsError(try settings.overrides())
    }
    func testBatchLaunchKeepsWorkingDirectoryAndQuotesSpaces() throws {
        let engine = try file("wine", executable: true)
        let batch = try file("mod folder/launch.bat")
        var game = Game(bottleID: UUID(), name: "Mod", executable: batch.path, arguments: ["config with spaces.toml"])
        game.options.mods.dllOverrides = "winmm=n"
        let command = try WineCommand.launch(engine: engine, prefix: root, game: game)
        XCTAssertEqual(Array(command.arguments.prefix(4)), ["cmd", "/d", "/s", "/c"])
        XCTAssertTrue(command.arguments[4].hasPrefix("\"\"Z:"))
        XCTAssertTrue(command.arguments[4].contains("\"config with spaces.toml\""))
        XCTAssertEqual(command.workingDirectory?.path, batch.deletingLastPathComponent().path)
        XCTAssertTrue(command.environment["WINEDLLOVERRIDES"]!.contains("winmm=n"))
        game.arguments = ["%PATH% & another.exe"]
        XCTAssertThrowsError(try WineCommand.launch(engine: engine, prefix: root, game: game))
    }
    func testSteamUsesBottleClientAndExcludesGameOverrides() throws {
        let engine = try file("wine", executable: true)
        let steam = try file("prefix/drive_c/Program Files (x86)/Steam/steam.exe")
        var game = Game(bottleID: UUID(), name: "Mod", executable: try pe("x64").path)
        game.options.mods.steamURL = "steam://run/480"
        game.options.mods.dllOverrides = "winmm=n"
        let prefix = root.appendingPathComponent("prefix")
        let command = try WineCommand.steam(engine: engine, prefix: prefix, game: game, configuration: RuntimeConfiguration())
        XCTAssertEqual(command.arguments, [steam.path, "steam://run/480"])
        XCTAssertEqual(command.environment["WINEPREFIX"], prefix.path)
        XCTAssertNil(command.environment["WINEDLLOVERRIDES"])
        game.options.mods.steamURL = "https://example.com"
        XCTAssertThrowsError(try WineCommand.steam(engine: engine, prefix: prefix, game: game, configuration: RuntimeConfiguration()))
        game.options.mods.steamURL = ""
        game.options.mods.steamExecutable = try file("outside/steam.exe").path
        XCTAssertThrowsError(try WineCommand.steam(engine: engine, prefix: prefix, game: game, configuration: RuntimeConfiguration()))
    }
    func testSyncCapabilityAndRosettaArgumentBoundaries() throws {
        let engine = try file("engine with spaces/bin/wine", executable: true)
        var game = Game(bottleID: UUID(), name: "Game", executable: try pe("x64").path, arguments: ["one two"])
        game.options.synchronization = .msync
        game.options.rosetta = true
        XCTAssertThrowsError(try WineCommand.launch(engine: engine, prefix: root, game: game))
        var config = RuntimeConfiguration(); config.supportsMSync = true
        let command = try WineCommand.launch(engine: engine, prefix: root, game: game, configuration: config)
        XCTAssertEqual(command.executable.path, "/usr/bin/arch")
        XCTAssertEqual(command.arguments, ["-x86_64", engine.path, game.executable, "one two"])
        XCTAssertEqual(command.environment["WINEMSYNC"], "1")
        XCTAssertEqual(command.environment["WINEESYNC"], "0")
    }
    func testDXVKBackupIsNotReplacedOnReinstall() throws {
        try file("package/x64/d3d11.dll", data: Data("dxvk".utf8))
        try file("package/x64/dxgi.dll")
        let original = try file("prefix/drive_c/windows/system32/d3d11.dll")
        let prefix = root.appendingPathComponent("prefix")
        for _ in 0..<2 { try GraphicsRuntime.installDXVK(from: root.appendingPathComponent("package"), prefix: prefix) }
        XCTAssertEqual(try Data(contentsOf: original), Data("dxvk".utf8))
        XCTAssertEqual(try Data(contentsOf: prefix.appendingPathComponent(".miras-dll-backups/system32/d3d11.dll")), Data("original".utf8))
    }
    func testMissingDXVKDLLFailsBeforeChangingPrefix() throws {
        try file("package/x64/d3d11.dll", data: Data("new".utf8))
        let original = try file("prefix/drive_c/windows/system32/d3d11.dll")
        XCTAssertThrowsError(try GraphicsRuntime.installDXVK(from: root.appendingPathComponent("package"), prefix: root.appendingPathComponent("prefix")))
        XCTAssertEqual(try Data(contentsOf: original), Data("original".utf8))
    }
    func testRendererRejectsMissing32BitPackage() throws {
        let engine = try file("wine", executable: true)
        var game = Game(bottleID: UUID(), name: "32-bit", executable: try pe("x32").path)
        game.options.graphics = .dxvk
        try file("package/x64/d3d11.dll"); try file("package/x64/dxgi.dll")
        var config = RuntimeConfiguration(); config.dxvkPath = root.appendingPathComponent("package").path
        XCTAssertThrowsError(try WineCommand.launch(engine: engine, prefix: root, game: game, configuration: config))
        game.options.graphics = .d3dMetal; config.d3dMetalReady = true
        XCTAssertThrowsError(try WineCommand.launch(engine: engine, prefix: root, game: game, configuration: config))
    }
    func testWinetricksUsesSelectedWineAndPrefix() throws {
        let engine = try file("wine", executable: true)
        let tool = try file("winetricks", executable: true)
        let command = try WineCommand.dependencies(engine: engine, prefix: root, tool: tool, verbs: [.vcrun2022, .dotnet48])
        XCTAssertEqual(command.arguments, ["-q", "vcrun2022", "dotnet48"])
        XCTAssertEqual(command.environment["WINE"], engine.path)
        XCTAssertEqual(command.environment["WINEPREFIX"], root.path)
        XCTAssertEqual(command.executable, tool)
    }
    func testGPTKImportLeavesOriginalEngineUntouched() throws {
        let engine = try file("engine/bin/wine", executable: true)
        let original = try file("engine/lib/wine/x86_64-windows/d3d11.dll")
        try file("redist/lib/wine/x86_64-windows/d3d11.dll", data: Data("metal".utf8))
        try file("redist/lib/wine/x86_64-windows/d3d12.dll")
        try file("redist/lib/external/D3DMetal.framework/D3DMetal")
        let imported = try EngineImporter.importD3DMetal(engine: engine, redistLib: root.appendingPathComponent("redist/lib"), destination: root.appendingPathComponent("managed"))
        XCTAssertEqual(imported.path, root.appendingPathComponent("managed/bin/wine").path)
        XCTAssertEqual(try Data(contentsOf: original), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("managed/lib/wine/x86_64-windows/d3d11.dll")), Data("metal".utf8))
    }
}
