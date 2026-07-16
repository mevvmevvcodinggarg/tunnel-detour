import XCTest
@testable import TunnelDetourCore

final class RouteManagerTests: XCTestCase {
    func testNormalizeHostStripsSchemePathAndPort() {
        XCTAssertEqual(RouteManager.normalizeHost("https://api.example.com:443/v1/models"), "api.example.com")
        XCTAssertEqual(RouteManager.normalizeHost(" API.EXAMPLE.COM "), "api.example.com")
    }

    func testInferResolverDomainUsesRegistrableTail() {
        XCTAssertEqual(RouteManager.inferResolverDomain(from: "api.example.com"), "example.com")
        XCTAssertEqual(RouteManager.inferResolverDomain(from: "claude.ai"), "claude.ai")
        XCTAssertNil(RouteManager.inferResolverDomain(from: "203.0.113.10"))
    }

    func testGeneratedApplyScriptRoutesPublicDNSBeforeResolvingDomains() {
        var config = TunnelDetourConfig.defaults
        config.customDomainTargets = [RouteTarget(kind: .domain, value: "api.example.com")]
        config.ipv4Targets = [RouteTarget(kind: .ipv4, value: "203.0.113.10")]
        config.resolverDomains = ["example.com"]

        let script = RouteManager.makeApplyScript(config: config, wifiGateway: "192.168.66.1")

        XCTAssertTrue(script.contains("/sbin/route -n add -host \"8.8.8.8\" \"192.168.66.1\""))
        XCTAssertTrue(script.contains("/etc/resolver/example.com"))
        XCTAssertTrue(script.contains("/usr/bin/dig @\"$dns\" +time=1 +tries=1 +short A \"$host\""))
        XCTAssertTrue(script.contains("/sbin/route -n add -host \"203.0.113.10\" \"192.168.66.1\""))

        let dnsRouteIndex = script.range(of: "/sbin/route -n add -host \"8.8.8.8\"")!.lowerBound
        let digIndex = script.range(of: "/usr/bin/dig @\"$dns\"")!.lowerBound
        XCTAssertLessThan(dnsRouteIndex, digIndex)
    }

    func testApplyScriptResolvesDomainsWithBoundedParallelWorkers() {
        var config = TunnelDetourConfig.defaults
        config.customDomainTargets = [
            RouteTarget(kind: .domain, value: "one.example.com"),
            RouteTarget(kind: .domain, value: "two.example.com")
        ]

        let script = RouteManager.makeApplyScript(config: config, wifiGateway: "192.168.66.1")

        XCTAssertTrue(script.contains("/usr/bin/xargs -P 12 -n 1"))
        XCTAssertTrue(script.contains("+time=1 +tries=1 +short A \"$host\""))
    }

    func testGeneratedApplyScriptHasValidBashSyntax() throws {
        let script = RouteManager.makeApplyScript(
            config: .defaults,
            wifiGateway: "192.168.66.1",
            directCIDRs: GoogleIPRanges.fallbackServiceIPv4CIDRs
        )
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnel-detour-syntax-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let result = try RouteManager.run("/bin/bash", arguments: ["-n", scriptURL.path])

        XCTAssertEqual(result.exitCode, 0)
    }

    func testApplyScriptContinuesWhenDomainHasNoIPv4Records() {
        var config = TunnelDetourConfig.defaults
        config.customDomainTargets = [RouteTarget(kind: .domain, value: "missing.example.com")]

        let script = RouteManager.makeApplyScript(config: config, wifiGateway: "192.168.66.1")

        XCTAssertTrue(script.contains("/usr/bin/sort -u > \"$RESULT_FILE\" || true"))
        XCTAssertTrue(script.contains("No IPv4 records found"))
    }

    func testApplyScriptRoutesGoogleServiceCIDRsThroughWifi() {
        let script = RouteManager.makeApplyScript(
            config: .defaults,
            wifiGateway: "192.168.66.1",
            directCIDRs: ["142.250.0.0/15", "173.194.0.0/16"]
        )

        XCTAssertTrue(script.contains("/sbin/route -n add -net \"142.250.0.0/15\" \"192.168.66.1\""))
        XCTAssertTrue(script.contains("/sbin/route -n add -net \"173.194.0.0/16\" \"192.168.66.1\""))
    }

    func testVerifyScriptUsesDirectSitesWording() {
        let script = RouteManager.makeVerifyScript(config: .defaults)

        XCTAssertTrue(script.contains("== Direct site routes =="))
        XCTAssertFalse(script.contains("Bypass domain routes"))
    }

    func testRepairScriptUsesOnlyNormalizedHostFromRequestURL() throws {
        let input = "https://rr4---sn-8qj-i5ozr.googlevideo.com/videoplayback?fixture=value"

        let script = try RouteManager.makeRepairScript(
            input: input,
            wifiGateway: "192.168.66.1",
            publicDNS: ["8.8.8.8", "1.1.1.1"]
        )

        XCTAssertTrue(script.contains("/sbin/route -n add -host \"8.8.8.8\" \"$GW\""))
        XCTAssertTrue(script.contains("+short A \"rr4---sn-8qj-i5ozr.googlevideo.com\""))
        XCTAssertTrue(script.contains("/sbin/route -n add -host \"$ip\" \"$GW\""))
        XCTAssertFalse(script.contains("videoplayback"))
        XCTAssertFalse(script.contains("sensitive"))

        let dnsRouteIndex = script.range(of: "/sbin/route -n add -host \"8.8.8.8\"")!.lowerBound
        let lookupIndex = script.range(of: "/usr/bin/dig")!.lowerBound
        XCTAssertLessThan(dnsRouteIndex, lookupIndex)
    }

    func testRepairScriptRoutesIPv4WithoutDNSLookup() throws {
        let script = try RouteManager.makeRepairScript(
            input: "113.171.203.143",
            wifiGateway: "192.168.66.1",
            publicDNS: ["8.8.8.8"]
        )

        XCTAssertTrue(script.contains("/sbin/route -n add -host \"113.171.203.143\" \"$GW\""))
        XCTAssertFalse(script.contains("/usr/bin/dig"))
    }

    func testGeneratedRepairScriptsHaveValidBashSyntax() throws {
        let inputs = [
            "https://rr4---sn-8qj-i5ozr.googlevideo.com/videoplayback?fixture=value",
            "113.171.203.143"
        ]

        for input in inputs {
            let script = try RouteManager.makeRepairScript(
                input: input,
                wifiGateway: "192.168.66.1",
                publicDNS: ["8.8.8.8", "1.1.1.1"]
            )
            let scriptURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("tunnel-detour-repair-syntax-\(UUID().uuidString).sh")
            defer { try? FileManager.default.removeItem(at: scriptURL) }
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)

            let result = try RouteManager.run("/bin/bash", arguments: ["-n", scriptURL.path])

            XCTAssertEqual(result.exitCode, 0)
        }
    }

    func testRunTerminatesProcessAfterTimeout() {
        XCTAssertThrowsError(
            try RouteManager.run("/bin/sleep", arguments: ["1"], timeout: 0.05)
        ) { error in
            guard case RouteManagerError.commandTimedOut = error else {
                return XCTFail("Expected a command timeout, got \(error)")
            }
        }
    }
}
