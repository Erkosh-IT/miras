import Foundation

public struct ModSettings: Codable, Equatable {
    public var dllOverrides = ""
    public var steamExecutable = ""
    public var steamURL = ""
    public var batchArchitecture = "x64"
    public init() {}

    public func overrides() throws -> [String: String] {
        var result: [String: String] = [:]
        let graphics = Set(["d3d9", "d3d10", "d3d10_1", "d3d10core", "d3d11", "dxgi", "d3d12"])
        for line in dllOverrides.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let parts = line.lowercased().split(separator: "=", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].range(of: "^[a-z0-9_-]+$", options: .regularExpression) != nil,
                  ["n", "b", "n,b", "b,n", ""].contains(parts[1]) else {
                throw ConfigurationError("DLL overrides must use one name=mode per line, for example winmm=n or version=n,b. Omit .dll from the name.")
            }
            guard !graphics.contains(parts[0]) else { throw ConfigurationError("Choose the graphics backend with the Graphics setting instead of overriding \(parts[0]).") }
            result[parts[0]] = parts[1]
        }
        return result
    }
    public func validatedSteamURL() throws -> String? {
        let value = steamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        guard value.range(of: "^steam://(run|rungameid)/[0-9]+$", options: .regularExpression) != nil else {
            throw ConfigurationError("Use steam://run/<numeric AppID> or steam://rungameid/<numeric AppID>.")
        }
        return value
    }
}
