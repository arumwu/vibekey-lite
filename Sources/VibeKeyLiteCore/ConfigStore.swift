import Foundation

public final class ConfigStore {
    public let configURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configURL: URL, fileManager: FileManager = .default) {
        self.configURL = configURL
        self.fileManager = fileManager

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public static func defaultConfigURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )

        return applicationSupport
            .appendingPathComponent("VibeKey Lite", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    public func loadOrCreate() throws -> AppConfiguration {
        guard fileManager.fileExists(atPath: configURL.path) else {
            let configuration = AppConfiguration.default
            try save(configuration)
            return configuration
        }

        let data = try Data(contentsOf: configURL)
        return try decoder.decode(AppConfiguration.self, from: data)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let directory = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try encoder.encode(configuration)
        try data.write(to: configURL, options: .atomic)
    }
}
