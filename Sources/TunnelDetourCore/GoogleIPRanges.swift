import Foundation

public enum GoogleIPRangeError: LocalizedError {
    case invalidResponse
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Google IP range response was invalid."
        case .requestFailed(let message):
            return message
        }
    }
}

public enum GoogleIPRanges {
    public static let googleRangesURL = URL(string: "https://www.gstatic.com/ipranges/goog.json")!
    public static let cloudRangesURL = URL(string: "https://www.gstatic.com/ipranges/cloud.json")!

    public static let fallbackServiceIPv4CIDRs = [
        "8.8.4.0/24",
        "8.8.8.0/24",
        "64.233.160.0/19",
        "66.102.0.0/20",
        "66.249.64.0/19",
        "72.14.192.0/18",
        "74.125.0.0/16",
        "108.170.192.0/18",
        "108.177.0.0/17",
        "142.250.0.0/15",
        "172.217.0.0/16",
        "172.253.0.0/16",
        "173.194.0.0/16",
        "192.178.0.0/15",
        "208.65.152.0/22",
        "208.117.224.0/19",
        "209.85.128.0/17",
        "216.58.192.0/19",
        "216.239.32.0/19"
    ]

    public static let regionalMediaCacheIPv4CIDRs = [
        "113.171.194.0/24",
        "113.171.203.0/24"
    ]

    public static var defaultCacheURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return applicationSupport
            .appendingPathComponent(ProductIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("google-service-ranges.json")
    }

    public static func loadCachedOrFallback(cacheURL: URL? = nil) -> [String] {
        let url = cacheURL ?? defaultCacheURL
        guard let data = try? Data(contentsOf: url),
              let ranges = try? JSONDecoder().decode([String].self, from: data),
              areValid(ranges) else {
            return fallbackServiceIPv4CIDRs
        }
        return ranges
    }

    public static func directServiceRoutes(cacheURL: URL? = nil) -> [String] {
        var seen = Set<String>()
        return (loadCachedOrFallback(cacheURL: cacheURL) + regionalMediaCacheIPv4CIDRs)
            .filter { seen.insert($0).inserted }
    }

    public static func saveCache(_ ranges: [String], cacheURL: URL? = nil) throws {
        guard areValid(ranges) else {
            throw GoogleIPRangeError.invalidResponse
        }

        let url = cacheURL ?? defaultCacheURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(ranges).write(to: url, options: .atomic)
    }

    public static func refreshCache(cacheURL: URL? = nil) throws {
        try saveCache(fetchDirectServiceIPv4CIDRs(), cacheURL: cacheURL)
    }

    public static func fetchDirectServiceIPv4CIDRs() throws -> [String] {
        let googleData = try fetch(googleRangesURL)
        let cloudData = try fetch(cloudRangesURL)
        return try directServiceIPv4CIDRs(googleData: googleData, cloudData: cloudData)
    }

    public static func directServiceIPv4CIDRs(googleData: Data, cloudData: Data) throws -> [String] {
        let decoder = JSONDecoder()
        let google = try decoder.decode(IPRangeDocument.self, from: googleData)
        let cloud = try decoder.decode(IPRangeDocument.self, from: cloudData)

        let googleRanges = google.prefixes.compactMap(\.ipv4Prefix).compactMap { IPv4Range(cidr: $0) }
        let cloudRanges = cloud.prefixes.compactMap(\.ipv4Prefix).compactMap { IPv4Range(cidr: $0) }
        guard !googleRanges.isEmpty else {
            throw GoogleIPRangeError.invalidResponse
        }

        return subtract(merge(googleRanges), excluding: merge(cloudRanges))
            .flatMap(\.cidrs)
    }

    private static func fetch(_ url: URL) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        var statusCode: Int?
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 6

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            responseError = error
            statusCode = (response as? HTTPURLResponse)?.statusCode
            semaphore.signal()
        }
        task.resume()

        guard semaphore.wait(timeout: .now() + 8) == .success else {
            task.cancel()
            throw GoogleIPRangeError.requestFailed("Google IP range request timed out.")
        }
        guard responseError == nil,
              let responseData,
              let statusCode,
              (200...299).contains(statusCode) else {
            throw GoogleIPRangeError.requestFailed("Could not load Google IP ranges.")
        }
        return responseData
    }

    private static func areValid(_ ranges: [String]) -> Bool {
        !ranges.isEmpty && ranges.allSatisfy { IPv4Range(cidr: $0) != nil }
    }

    private static func merge(_ ranges: [IPv4Range]) -> [IPv4Range] {
        let sorted = ranges.sorted {
            $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
        }
        guard var current = sorted.first else { return [] }

        var result: [IPv4Range] = []
        for range in sorted.dropFirst() {
            if UInt64(range.start) <= UInt64(current.end) + 1 {
                current = IPv4Range(start: current.start, end: max(current.end, range.end))
            } else {
                result.append(current)
                current = range
            }
        }
        result.append(current)
        return result
    }

    private static func subtract(_ ranges: [IPv4Range], excluding exclusions: [IPv4Range]) -> [IPv4Range] {
        var result: [IPv4Range] = []

        for range in ranges {
            var cursor = UInt64(range.start)
            let rangeEnd = UInt64(range.end)

            for exclusion in exclusions {
                let exclusionStart = UInt64(exclusion.start)
                let exclusionEnd = UInt64(exclusion.end)
                if exclusionEnd < cursor || exclusionStart > rangeEnd {
                    continue
                }

                if exclusionStart > cursor {
                    result.append(IPv4Range(
                        start: UInt32(cursor),
                        end: UInt32(min(rangeEnd, exclusionStart - 1))
                    ))
                }

                cursor = max(cursor, exclusionEnd + 1)
                if cursor > rangeEnd {
                    break
                }
            }

            if cursor <= rangeEnd {
                result.append(IPv4Range(start: UInt32(cursor), end: UInt32(rangeEnd)))
            }
        }

        return result
    }
}

private struct IPRangeDocument: Decodable {
    let prefixes: [IPRangePrefix]
}

private struct IPRangePrefix: Decodable {
    let ipv4Prefix: String?
    let ipv6Prefix: String?
}

private struct IPv4Range {
    let start: UInt32
    let end: UInt32

    init?(cidr: String) {
        let components = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              let address = Self.parseAddress(String(components[0])),
              let prefix = Int(components[1]),
              (0...32).contains(prefix) else {
            return nil
        }

        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
        start = address & mask
        end = start | ~mask
    }

    init(start: UInt32, end: UInt32) {
        self.start = start
        self.end = end
    }

    var cidrs: [String] {
        var result: [String] = []
        var cursor = UInt64(start)
        let final = UInt64(end)

        while cursor <= final {
            let address = UInt32(cursor)
            let alignmentBits = address == 0 ? 32 : address.trailingZeroBitCount
            let remaining = final - cursor + 1
            let sizeBits = 63 - remaining.leadingZeroBitCount
            let hostBits = min(min(alignmentBits, sizeBits), 32)
            let prefix = 32 - hostBits

            result.append("\(Self.formatAddress(address))/\(prefix)")
            cursor += UInt64(1) << UInt64(hostBits)
        }

        return result
    }

    private static func parseAddress(_ value: String) -> UInt32? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var address: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            address = (address << 8) | UInt32(byte)
        }
        return address
    }

    private static func formatAddress(_ value: UInt32) -> String {
        [24, 16, 8, 0]
            .map { String((value >> UInt32($0)) & 0xff) }
            .joined(separator: ".")
    }
}
