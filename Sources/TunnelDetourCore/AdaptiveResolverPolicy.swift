import Foundation

public enum AdaptiveResolverPolicy {
    public static let ownedContents = "nameserver 127.0.0.1\nport 55353\ntimeout 2\n"

    public static func isOwned(_ data: Data) -> Bool {
        guard let value = String(data: data, encoding: .utf8) else { return false }
        let directives = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return directives == [
            "nameserver 127.0.0.1",
            "port 55353",
            "timeout 2"
        ]
    }

    public static func ownedResolverURLs(
        in directory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try files.filter { file in
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true,
                  let data = try? Data(contentsOf: file) else { return false }
            return isOwned(data)
        }.sorted { $0.path < $1.path }
    }
}
