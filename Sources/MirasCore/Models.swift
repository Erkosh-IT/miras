import Foundation

public struct Bottle: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct Game: Codable, Identifiable, Equatable {
    public var id: UUID
    public var bottleID: UUID
    public var name: String
    public var executable: String
    public var arguments: [String]
    public var launchSettings: LaunchSettings?
    public var options: LaunchSettings {
        get { launchSettings ?? LaunchSettings() }
        set { launchSettings = newValue }
    }
    public init(id: UUID = UUID(), bottleID: UUID, name: String, executable: String, arguments: [String] = []) {
        self.id = id
        self.bottleID = bottleID
        self.name = name
        self.executable = executable
        self.arguments = arguments
    }
}

public struct Library: Codable, Equatable {
    public var bottles: [Bottle] = []
    public var games: [Game] = []
    public var enginePath: String = ""
    public var runtime: RuntimeConfiguration?
    public var configuration: RuntimeConfiguration {
        get { runtime ?? RuntimeConfiguration() }
        set { runtime = newValue }
    }
    public init() {}
}

public struct LibraryStore {
    public let root: URL
    public init(root: URL) { self.root = root }
    public func prefix(for bottle: Bottle) -> URL {
        root.appendingPathComponent("Bottles", isDirectory: true).appendingPathComponent(bottle.id.uuidString, isDirectory: true)
    }
    public func load() throws -> Library {
        let file = root.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return Library() }
        return try JSONDecoder().decode(Library.self, from: Data(contentsOf: file))
    }
    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: root.appendingPathComponent("library.json"), options: .atomic)
    }
}
