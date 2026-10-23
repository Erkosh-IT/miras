import Foundation
import XCTest
@testable import MirasCore

final class MirasCoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func fakeFile(_ name: String, executable: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        return url
    }

    func testLibraryRoundTripAndPrefixIsolation() throws {
        let store = LibraryStore(root: root)
        XCTAssertEqual(try store.load(), Library())
        var library = Library()
        let first = Bottle(name: "../../same name")
        let second = Bottle(name: "../../same name")
        library.bottles = [first, second]
        library.games = [Game(bottleID: first.id, name: "Game", executable: "/tmp/a game.exe", arguments: ["--flag"])]
        library.enginePath = "/custom/wine"
        try store.save(library)
        XCTAssertEqual(try store.load(), library)
        XCTAssertNotEqual(store.prefix(for: first), store.prefix(for: second))
        XCTAssertEqual(store.prefix(for: first).lastPathComponent, first.id.uuidString)
        XCTAssertEqual(store.prefix(for: first).deletingLastPathComponent().lastPathComponent, "Bottles")
    }

    func testCorruptLibraryThrowsWithoutOverwriting() throws {
        let file = root.appendingPathComponent("library.json")
        let bad = Data("broken".utf8)
        try bad.write(to: file)
        XCTAssertThrowsError(try LibraryStore(root: root).load())
        XCTAssertEqual(try Data(contentsOf: file), bad)
    }

    func testArgumentsAndEnvironmentArePassedLiterally() throws {
        let engine = try fakeFile("wine", executable: true)
        let exe = try fakeFile("game ; $(touch nope).exe")
        let prefix = root.appendingPathComponent("bottle with spaces")
        let game = Game(bottleID: UUID(), name: "Game", executable: exe.path, arguments: ["--name", "a b", "$(echo nope)"])
        let command = try WineCommand.launch(engine: engine, prefix: prefix, game: game)
        XCTAssertEqual(command.arguments, [exe.path, "--name", "a b", "$(echo nope)"])
        XCTAssertEqual(command.environment["WINEPREFIX"], prefix.path)
        XCTAssertEqual(command.workingDirectory?.standardizedFileURL.path, root.standardizedFileURL.path)
        XCTAssertTrue(command.environment["PATH"]!.hasPrefix(root.path + ":"))
    }

    func testInstallerDispatchAndValidation() throws {
        let engine = try fakeFile("wine", executable: true)
        let msi = try fakeFile("setup.MSI")
        let exe = try fakeFile("setup.exe")
        let other = try fakeFile("setup.txt")
        XCTAssertEqual(try WineCommand.install(engine: engine, prefix: root, installer: msi).arguments, ["msiexec", "/i", msi.path])
        XCTAssertEqual(try WineCommand.install(engine: engine, prefix: root, installer: exe).arguments, [exe.path])
        XCTAssertThrowsError(try WineCommand.install(engine: engine, prefix: root, installer: other))
        let missing = root.appendingPathComponent("missing.exe")
        XCTAssertThrowsError(try WineCommand.install(engine: engine, prefix: root, installer: missing))
    }

    func testInitializationAndStopArePrefixScoped() throws {
        let engine = try fakeFile("wine", executable: true)
        let prefix = root.appendingPathComponent("isolated")
        XCTAssertEqual(try WineCommand.initialize(engine: engine, prefix: prefix).arguments, ["wineboot", "--init"])
        XCTAssertThrowsError(try WineCommand.stop(engine: engine, prefix: prefix))
        let server = try fakeFile("wineserver", executable: true)
        let stop = try WineCommand.stop(engine: engine, prefix: prefix)
        XCTAssertEqual(stop.executable, server)
        XCTAssertEqual(stop.arguments, ["-k"])
        XCTAssertEqual(stop.environment["WINEPREFIX"], prefix.path)
    }

    func testMissingEngineAndGameFailBeforeLaunch() throws {
        let missingEngine = root.appendingPathComponent("missing-wine")
        XCTAssertThrowsError(try WineCommand.initialize(engine: missingEngine, prefix: root))
        let notExecutable = try fakeFile("wine")
        XCTAssertThrowsError(try WineCommand.initialize(engine: notExecutable, prefix: root))
        let engine = try fakeFile("real-wine", executable: true)
        let game = Game(bottleID: UUID(), name: "Gone", executable: root.appendingPathComponent("gone.exe").path)
        XCTAssertThrowsError(try WineCommand.launch(engine: engine, prefix: root, game: game))
    }
}
