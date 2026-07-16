import XCTest
@testable import TunnelDetourCore

final class ConfigStoreTests: XCTestCase {
    func testPublicProductIdentityIsStable() {
        XCTAssertEqual(ProductIdentity.name, "TunnelDetour")
        XCTAssertEqual(ProductIdentity.bundleIdentifier, "io.github.mevvmevvcodinggarg.tunneldetour")
        XCTAssertEqual(ProductIdentity.helperExecutableName, "TunnelDetourHelper")
    }

    func testServiceFilterMatchesNameCategoryAndIdentifier() {
        let groups = [
            ServiceDirectGroup(id: "workspace-tool", category: "Collaboration", name: "Task Desk", domains: ["clickup.com"]),
            ServiceDirectGroup(id: "source-control", category: "Developer", name: "Code Hub", domains: ["github.com"])
        ]

        XCTAssertEqual(ServiceFilter.matchingGroups(groups, query: "task desk").map(\.id), ["workspace-tool"])
        XCTAssertEqual(ServiceFilter.matchingGroups(groups, query: "developer").map(\.id), ["source-control"])
        XCTAssertEqual(ServiceFilter.matchingGroups(groups, query: "SOURCE-CONTROL").map(\.id), ["source-control"])
    }

    func testServiceFilterReturnsAllGroupsForBlankQuery() {
        let groups = TunnelDetourConfig.serviceGroups

        XCTAssertEqual(ServiceFilter.matchingGroups(groups, query: "  "), groups)
    }

    func testServiceFilterDoesNotReturnUnrelatedCategories() {
        let groups = TunnelDetourConfig.serviceGroups
        let matching = ServiceFilter.matchingGroups(groups, query: "Observability")
        let expectedIDs = Set(groups.filter { $0.category == "Observability" }.map(\.id))

        XCTAssertFalse(matching.isEmpty)
        XCTAssertTrue(matching.allSatisfy { $0.category == "Observability" })
        XCTAssertEqual(Set(matching.map(\.id)), expectedIDs)
    }

    func testDefaultConfigUsesGenericOptionalPrivateCheck() {
        let config = TunnelDetourConfig.defaults

        XCTAssertEqual(config.schemaVersion, 8)
        XCTAssertEqual(config.enabledServiceIDs, Set(TunnelDetourConfig.serviceGroups.map(\.id)))
        XCTAssertTrue(config.customDomainTargets.isEmpty)
        XCTAssertTrue(config.googleServicesDirect)
        XCTAssertTrue(config.adaptiveDirectSites)
        XCTAssertEqual(config.wifiInterface, "en0")
        XCTAssertEqual(config.publicDNS, ["8.8.8.8", "1.1.1.1"])
        XCTAssertTrue(config.domainTargets.contains(RouteTarget(kind: .domain, value: "api.openai.com")))
        XCTAssertTrue(config.domainTargets.contains(RouteTarget(kind: .domain, value: "chatgpt.com")))
        XCTAssertTrue(config.domainTargets.contains(RouteTarget(kind: .domain, value: "api.anthropic.com")))
        XCTAssertTrue(config.domainTargets.contains(RouteTarget(kind: .domain, value: "claude.ai")))
        XCTAssertTrue(config.resolverDomains.contains("openai.com"))
        XCTAssertEqual(config.privateCheckHost, "")
    }

    func testOlderConfigEnablesAdaptiveDirectSitesDuringMigration() throws {
        let data = try JSONEncoder().encode(TunnelDetourConfig.defaults)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 4
        object.removeValue(forKey: "adaptiveDirectSites")

        let decoded = try JSONDecoder().decode(
            TunnelDetourConfig.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(TunnelDetourConfig.migratedToCurrentDefaults(decoded).adaptiveDirectSites)
    }

    func testDefaultConfigContainsExpandedCommonDirectSites() {
        let values = Set(TunnelDetourConfig.defaults.domainTargets.map(\.value))

        XCTAssertTrue(values.contains("www.google.com"))
        XCTAssertTrue(values.contains("gemini.google.com"))
        XCTAssertTrue(values.contains("www.youtube.com"))
        XCTAssertTrue(values.contains("youtu.be"))
        XCTAssertTrue(values.contains("youtube-nocookie.com"))
        XCTAssertTrue(values.contains("googlevideo.com"))
        XCTAssertTrue(values.contains("ytimg.com"))
        XCTAssertTrue(TunnelDetourConfig.defaults.resolverDomains.contains("googlevideo.com"))
        XCTAssertTrue(TunnelDetourConfig.defaults.resolverDomains.contains("youtube-nocookie.com"))
        XCTAssertTrue(values.contains("github.com"))
        XCTAssertTrue(values.contains("npmjs.org"))
        XCTAssertTrue(TunnelDetourConfig.defaults.resolverDomains.contains("npmjs.org"))
        XCTAssertTrue(values.contains("stackoverflow.com"))
        XCTAssertTrue(values.contains("discord.com"))
        XCTAssertTrue(values.contains("open.spotify.com"))
        XCTAssertTrue(values.contains("wikipedia.org"))
        XCTAssertTrue(values.contains("cdn.jsdelivr.net"))
        XCTAssertTrue(values.contains("fast.com"))
        XCTAssertTrue(values.contains("clickup.com"))
        XCTAssertTrue(values.contains("postman.com"))
        XCTAssertTrue(values.contains("atlassian.net"))
        XCTAssertTrue(values.contains("figma.com"))
        XCTAssertTrue(values.contains("sentry.io"))
    }

    func testDisabledServiceDoesNotContributeDomainsButCustomDomainRemains() {
        var config = TunnelDetourConfig.defaults
        config.enabledServiceIDs.remove("postman")
        config.customDomainTargets = [RouteTarget(kind: .domain, value: "custom.example.com")]

        XCTAssertFalse(config.domainTargets.contains(RouteTarget(kind: .domain, value: "postman.com")))
        XCTAssertTrue(config.domainTargets.contains(RouteTarget(kind: .domain, value: "custom.example.com")))
    }

    func testDisabledPreviousServiceExcludesItsPreviousSubdomains() {
        var config = TunnelDetourConfig.defaults
        config.enabledServiceIDs.remove("slack")

        XCTAssertFalse(config.domainTargets.contains(RouteTarget(kind: .domain, value: "app.slack.com")))
        XCTAssertFalse(config.domainTargets.contains(RouteTarget(kind: .domain, value: "slack-edge.com")))
    }

    func testServiceDomainsUseFirstPartyRoots() throws {
        let groups = Dictionary(uniqueKeysWithValues: TunnelDetourConfig.serviceGroups.map { ($0.id, $0) })

        XCTAssertTrue(try XCTUnwrap(groups["slack"]).domains.contains("slack.com"))
        XCTAssertTrue(try XCTUnwrap(groups["clickup"]).domains.contains("clickup.com"))
        XCTAssertTrue(try XCTUnwrap(groups["postman"]).domains.contains("postman.com"))
        XCTAssertTrue(try XCTUnwrap(groups["atlassian"]).domains.contains("atlassian.net"))
        XCTAssertTrue(try XCTUnwrap(groups["figma"]).domains.contains("figma.com"))
    }

    func testConfigStorePersistsCustomDomainAndIPTargets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempDirectory.appendingPathComponent("config.json")
        let store = ConfigStore(configURL: configURL)

        var config = TunnelDetourConfig.defaults
        config.customDomainTargets.append(RouteTarget(kind: .domain, value: "api.example.com"))
        config.ipv4Targets.append(RouteTarget(kind: .ipv4, value: "203.0.113.10"))

        try store.save(config)
        let loaded = try store.load()

        XCTAssertTrue(loaded.customDomainTargets.contains(RouteTarget(kind: .domain, value: "api.example.com")))
        XCTAssertTrue(loaded.domainTargets.contains(RouteTarget(kind: .domain, value: "api.example.com")))
        XCTAssertEqual(loaded.ipv4Targets.last, RouteTarget(kind: .ipv4, value: "203.0.113.10"))
    }

    func testMissingConfigLoadsDefaults() throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("config.json")
        let store = ConfigStore(configURL: configURL)

        XCTAssertEqual(try store.load(), TunnelDetourConfig.defaults)
    }

    func testConfigStoreMigratesOlderConfigByMergingCurrentDefaultSites() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempDirectory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try """
        {
          "wifiInterface" : "en0",
          "publicDNS" : ["8.8.8.8", "1.1.1.1"],
          "domainTargets" : [
            { "kind" : "domain", "value" : "api.openai.com" },
            { "kind" : "domain", "value" : "custom.example.com" }
          ],
          "ipv4Targets" : [],
          "resolverDomains" : ["openai.com", "example.com"],
          "privateCheckHost" : "private.example.com"
        }
        """.data(using: .utf8)!.write(to: configURL)

        let store = ConfigStore(configURL: configURL)
        let loaded = try store.load()
        let values = Set(loaded.domainTargets.map(\.value))

        XCTAssertEqual(loaded.schemaVersion, TunnelDetourConfig.currentSchemaVersion)
        XCTAssertTrue(loaded.googleServicesDirect)
        XCTAssertTrue(values.contains("custom.example.com"))
        XCTAssertTrue(loaded.customDomainTargets.contains(RouteTarget(kind: .domain, value: "custom.example.com")))
        XCTAssertFalse(loaded.customDomainTargets.contains(RouteTarget(kind: .domain, value: "api.openai.com")))
        XCTAssertEqual(loaded.enabledServiceIDs, Set(TunnelDetourConfig.serviceGroups.map(\.id)))
        XCTAssertTrue(values.contains("www.google.com"))
        XCTAssertTrue(values.contains("npmjs.org"))
    }
}
