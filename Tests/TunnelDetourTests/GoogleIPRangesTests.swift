import XCTest
@testable import TunnelDetourCore

final class GoogleIPRangesTests: XCTestCase {
    func testMissingCacheUsesBundledFallbackWithoutNetworkAccess() {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("google-ranges.json")

        XCTAssertEqual(
            GoogleIPRanges.loadCachedOrFallback(cacheURL: cacheURL),
            GoogleIPRanges.fallbackServiceIPv4CIDRs
        )
    }

    func testSavedCacheIsUsedByApplyPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cacheURL = directory.appendingPathComponent("google-ranges.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let expected = ["142.250.0.0/15", "173.194.0.0/16"]
        try GoogleIPRanges.saveCache(expected, cacheURL: cacheURL)

        XCTAssertEqual(
            GoogleIPRanges.loadCachedOrFallback(cacheURL: cacheURL),
            expected
        )
    }

    func testMalformedCacheUsesBundledFallback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cacheURL = directory.appendingPathComponent("google-ranges.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: cacheURL)

        XCTAssertEqual(
            GoogleIPRanges.loadCachedOrFallback(cacheURL: cacheURL),
            GoogleIPRanges.fallbackServiceIPv4CIDRs
        )
    }

    func testSubtractsCloudCustomerRangeFromGoogleServiceRange() throws {
        let googleData = """
        {
          "prefixes": [
            { "ipv4Prefix": "142.250.0.0/15" },
            { "ipv4Prefix": "173.194.0.0/16" },
            { "ipv6Prefix": "2001:4860::/32" }
          ]
        }
        """.data(using: .utf8)!
        let cloudData = """
        {
          "prefixes": [
            { "ipv4Prefix": "142.250.0.0/16" }
          ]
        }
        """.data(using: .utf8)!

        let ranges = try GoogleIPRanges.directServiceIPv4CIDRs(
            googleData: googleData,
            cloudData: cloudData
        )

        XCTAssertEqual(ranges, ["142.251.0.0/16", "173.194.0.0/16"])
    }

    func testFallsBackToKnownGoogleServiceRanges() {
        XCTAssertTrue(GoogleIPRanges.fallbackServiceIPv4CIDRs.contains("142.250.0.0/15"))
        XCTAssertTrue(GoogleIPRanges.fallbackServiceIPv4CIDRs.contains("173.194.0.0/16"))
        XCTAssertTrue(GoogleIPRanges.fallbackServiceIPv4CIDRs.contains("216.239.32.0/19"))
    }

    func testDirectServiceRoutesIncludeObservedRegionalMediaCaches() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cacheURL = directory.appendingPathComponent("google-ranges.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let ranges = GoogleIPRanges.directServiceRoutes(cacheURL: cacheURL)

        XCTAssertTrue(ranges.contains("113.171.194.0/24"))
        XCTAssertTrue(ranges.contains("113.171.203.0/24"))
        XCTAssertTrue(ranges.contains("142.250.0.0/15"))
    }
}
