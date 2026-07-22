import Foundation

public struct ConfigStore {
    public let configURL: URL

    public init(configURL: URL? = nil) {
        if let configURL {
            self.configURL = configURL
        } else {
            let applicationSupport = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
            self.configURL = applicationSupport
                .appendingPathComponent(ProductIdentity.applicationSupportDirectoryName, isDirectory: true)
                .appendingPathComponent("config.json")
        }
    }

    public func load() throws -> TunnelDetourConfig {
        if FileManager.default.fileExists(atPath: configURL.path) {
            return try loadConfig(at: configURL)
        }

        return .defaults
    }

    public func save(_ config: TunnelDetourConfig) throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    private func loadConfig(at url: URL) throws -> TunnelDetourConfig {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(TunnelDetourConfig.self, from: data)
        let migrated = TunnelDetourConfig.migratedToCurrentDefaults(decoded)
        if migrated != decoded {
            try save(migrated)
        }
        return migrated
    }
}
