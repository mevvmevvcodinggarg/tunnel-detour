import XCTest
@testable import TunnelDetourCore

final class AdaptiveSupportTests: XCTestCase {
    func testIPCPathsAreSystemScopedAndUIDIsolated() {
        let directory = AdaptiveArtifacts.ipcDirectory(uid: 501)

        XCTAssertEqual(directory, "/Library/Application Support/TunnelDetour/IPC/501")
        XCTAssertEqual(
            AdaptiveArtifacts.requestPath(uid: 501),
            directory + "/adaptive-request.json"
        )
        XCTAssertEqual(
            AdaptiveArtifacts.responsePath(uid: 501),
            directory + "/adaptive-response.json"
        )
        XCTAssertFalse(directory.contains("/Users/"))
    }

    func testApplyRequestCarriesAdaptiveSettings() {
        let request = AdaptiveRequest.apply(config: .defaults, directCIDRs: ["142.250.0.0/15"])

        XCTAssertEqual(request.action, .apply)
        XCTAssertTrue(request.adaptiveEnabled)
        XCTAssertTrue(request.resolverDomains.contains("googlevideo.com"))
        XCTAssertEqual(request.directCIDRs, ["142.250.0.0/15"])
    }

    func testApplyRequestCanonicalizesDomainsBeforeHelperValidation() {
        var config = TunnelDetourConfig.defaults
        config.customDomainTargets = [
            RouteTarget(kind: .domain, value: "*.Example.com"),
            RouteTarget(kind: .domain, value: "example.com")
        ]

        let request = AdaptiveRequest.apply(config: config, directCIDRs: [])

        XCTAssertEqual(request.domainTargets.filter { $0 == "example.com" }.count, 1)
        XCTAssertFalse(request.domainTargets.contains { $0.contains("*") })
        XCTAssertTrue(request.resolverDomains.contains("example.com"))
    }

    func testLaunchDaemonPlistUsesPrivatePathsAndNoLogs() throws {
        let data = try AdaptiveArtifacts.launchDaemonPlist(
            helperPath: "/Library/PrivilegedHelperTools/com.tunnel-detour.adaptive-helper",
            requestPath: "/tmp/TunnelDetour/adaptive-request.json",
            responsePath: "/tmp/TunnelDetour/adaptive-response.json"
        )
        let plistObject = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        let plist = try XCTUnwrap(plistObject as? [String: Any])

        XCTAssertEqual(plist["StandardOutPath"] as? String, "/dev/null")
        XCTAssertEqual(plist["StandardErrorPath"] as? String, "/dev/null")
        XCTAssertEqual(plist["KeepAlive"] as? Bool, true)
    }

    func testAdaptiveApplyDefersDomainResolutionToDNSRelay() {
        XCTAssertFalse(AdaptiveBehavior.shouldPreResolveDomains(adaptiveEnabled: true))
        XCTAssertTrue(AdaptiveBehavior.shouldPreResolveDomains(adaptiveEnabled: false))
    }

    func testAdaptiveApplySkipsBulkCIDRInstallation() {
        XCTAssertFalse(AdaptiveBehavior.shouldInstallBulkCIDRs(
            googleServicesDirect: true,
            adaptiveEnabled: true
        ))
        XCTAssertTrue(AdaptiveBehavior.shouldInstallBulkCIDRs(
            googleServicesDirect: true,
            adaptiveEnabled: false
        ))
        XCTAssertFalse(AdaptiveBehavior.shouldInstallBulkCIDRs(
            googleServicesDirect: false,
            adaptiveEnabled: false
        ))
    }

    func testApplyDoesNotPruneExistingManagedRoutes() {
        XCTAssertFalse(AdaptiveBehavior.shouldPruneExistingRoutesDuringApply)
    }

    func testInstallRunsWhenServiceIsMissingEvenIfFilesMatch() {
        XCTAssertFalse(AdaptiveBehavior.shouldInstallHelper(
            helperMatches: true,
            plistMatches: true,
            serviceLoaded: true
        ))
        XCTAssertTrue(AdaptiveBehavior.shouldInstallHelper(
            helperMatches: true,
            plistMatches: true,
            serviceLoaded: false
        ))
        XCTAssertTrue(AdaptiveBehavior.shouldInstallHelper(
            helperMatches: false,
            plistMatches: true,
            serviceLoaded: true
        ))
        XCTAssertTrue(AdaptiveBehavior.shouldInstallHelper(
            helperMatches: true,
            plistMatches: false,
            serviceLoaded: true
        ))
    }

    func testDynamicRoutesSkipAlreadyManagedAddresses() {
        XCTAssertFalse(AdaptiveBehavior.shouldRefreshManagedRoute(
            alreadyManaged: true,
            force: false
        ))
        XCTAssertTrue(AdaptiveBehavior.shouldRefreshManagedRoute(
            alreadyManaged: true,
            force: true
        ))
        XCTAssertTrue(AdaptiveBehavior.shouldRefreshManagedRoute(
            alreadyManaged: false,
            force: false
        ))
    }

    func testDNSRepliesDoNotWaitForDynamicRouteInstallation() {
        XCTAssertTrue(AdaptiveBehavior.shouldReplyBeforeDynamicRouting)
    }

    func testDirectDNSSuppressesIPv6Answers() {
        XCTAssertTrue(AdaptiveBehavior.shouldSuppressIPv6ForDirectDomains)
    }

    func testResponseTimeoutAllowsSlowRestoreWithoutMaskingApplyFailures() {
        XCTAssertGreaterThanOrEqual(AdaptiveBehavior.responseTimeout(for: .restore), 300)
        XCTAssertEqual(AdaptiveBehavior.responseTimeout(for: .apply), 60)
        XCTAssertEqual(AdaptiveBehavior.responseTimeout(for: .repair), 60)
    }

    func testResolverFilesAreOnlyWrittenWhenContentsChange() {
        let contents = "nameserver 127.0.0.1\nport 55353\ntimeout 2\n"

        XCTAssertFalse(AdaptiveBehavior.shouldWriteResolver(
            existingContents: Data(contents.utf8),
            desiredContents: contents
        ))
        XCTAssertTrue(AdaptiveBehavior.shouldWriteResolver(
            existingContents: nil,
            desiredContents: contents
        ))
        XCTAssertTrue(AdaptiveBehavior.shouldWriteResolver(
            existingContents: Data("nameserver 8.8.8.8\n".utf8),
            desiredContents: contents
        ))
    }

    func testAdaptiveResolverPolicyRecognizesOwnedContents() {
        XCTAssertTrue(AdaptiveResolverPolicy.isOwned(Data("""
        nameserver 127.0.0.1
        port 55353
        timeout 2

        """.utf8)))
        XCTAssertTrue(AdaptiveResolverPolicy.isOwned(Data(
            " nameserver   127.0.0.1\r\nport 55353\r\ntimeout 2\r\n".utf8
        )))
    }

    func testAdaptiveResolverPolicyRejectsUnownedContents() {
        let values = [
            "nameserver 192.0.2.10\nnameserver 198.51.100.20\n",
            "nameserver 8.8.8.8\n",
            "nameserver 127.0.0.1\nport 55353\ntimeout 2\nsearch private.example\n",
            "nameserver 127.0.0.1\nport 53\ntimeout 2\n"
        ]
        for value in values {
            XCTAssertFalse(AdaptiveResolverPolicy.isOwned(Data(value.utf8)), value)
        }
    }

    func testAdaptiveResolverPolicyListsOnlyOwnedRegularFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let owned = directory.appendingPathComponent("google.com")
        let privateResolver = directory.appendingPathComponent("private.example.com")
        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        try Data(AdaptiveResolverPolicy.ownedContents.utf8).write(to: owned)
        try Data("nameserver 192.0.2.10\n".utf8).write(to: privateResolver)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let matches = try AdaptiveResolverPolicy.ownedResolverURLs(in: directory)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.lastPathComponent, owned.lastPathComponent)
    }

    func testOrderedHelperRemovalRunsRemovalAfterRestore() throws {
        var events: [String] = []
        try AdaptiveController.performOrderedRemoval(
            restore: { events.append("restore") },
            remove: { events.append("remove") }
        )
        XCTAssertEqual(events, ["restore", "remove"])
    }

    func testOrderedHelperRemovalStopsWhenRestoreFails() {
        enum TestError: Error { case restore }
        var removalRan = false
        XCTAssertThrowsError(try AdaptiveController.performOrderedRemoval(
            restore: { throw TestError.restore },
            remove: { removalRan = true }
        ))
        XCTAssertFalse(removalRan)
    }

    func testHelperRemovalDeletesAllTunnelDetourSystemArtifacts() {
        let script = AdaptiveArtifacts.helperRemovalScript()

        XCTAssertTrue(script.contains(AdaptiveArtifacts.plistPath))
        XCTAssertTrue(script.contains(AdaptiveArtifacts.helperPath))
        XCTAssertTrue(script.contains(AdaptiveArtifacts.systemSupportDirectory))
        XCTAssertTrue(script.contains("rm -rf"))
    }
}
