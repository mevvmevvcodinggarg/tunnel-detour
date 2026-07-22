import XCTest
@testable import TunnelDetourCore

final class ManagedRoutePolicyTests: XCTestCase {
    private func route(
        _ target: String,
        origin: ManagedRouteOrigin,
        lastSeen: Date
    ) -> ManagedRouteRecord {
        ManagedRouteRecord(
            identity: ManagedRouteIdentity(target: target, network: false),
            origin: origin,
            lastSeen: lastSeen
        )
    }

    func testGatewayLossEntersFailOpen() {
        XCTAssertEqual(
            ManagedRoutePolicy.transitionActions(
                previousGateway: "192.0.2.1",
                observedGateway: nil,
                hasActiveRequest: true
            ),
            [.enterFailOpen]
        )
    }

    func testGatewayChangeFailsOpenBeforeReapply() {
        XCTAssertEqual(
            ManagedRoutePolicy.transitionActions(
                previousGateway: "192.0.2.1",
                observedGateway: "198.51.100.1",
                hasActiveRequest: true
            ),
            [.enterFailOpen, .reapply]
        )
    }

    func testGatewayAvailabilityReappliesActiveRequest() {
        XCTAssertEqual(
            ManagedRoutePolicy.transitionActions(
                previousGateway: nil,
                observedGateway: "198.51.100.1",
                hasActiveRequest: true
            ),
            [.reapply]
        )
    }

    func testMissingGatewayKeepsActiveRequestFailOpen() {
        XCTAssertEqual(
            ManagedRoutePolicy.transitionActions(
                previousGateway: nil,
                observedGateway: nil,
                hasActiveRequest: true
            ),
            [.enterFailOpen]
        )
    }

    func testMatchingGatewayOrMissingRequestDoesNothing() {
        XCTAssertEqual(
            ManagedRoutePolicy.transitionActions(
                previousGateway: "192.0.2.1",
                observedGateway: "192.0.2.1",
                hasActiveRequest: true
            ),
            []
        )
        XCTAssertEqual(
            ManagedRoutePolicy.transitionActions(
                previousGateway: "192.0.2.1",
                observedGateway: nil,
                hasActiveRequest: false
            ),
            []
        )
    }

    func testExpiredDynamicRoutesAreRemoved() {
        let now = Date(timeIntervalSince1970: 50_000)
        let fresh = route(
            "198.51.100.1",
            origin: .dynamic,
            lastSeen: now.addingTimeInterval(-ManagedRoutePolicy.dynamicRouteTTL + 1)
        )
        let expired = route(
            "198.51.100.2",
            origin: .dynamic,
            lastSeen: now.addingTimeInterval(-ManagedRoutePolicy.dynamicRouteTTL - 1)
        )

        XCTAssertEqual(
            ManagedRoutePolicy.retainedDynamicRoutes([expired, fresh], now: now),
            [fresh]
        )
    }

    func testNewestDynamicRoutesSurviveHardCap() {
        let routes = (0..<(ManagedRoutePolicy.maxDynamicRoutes + 10)).map { index in
            route(
                "198.51.100.\(index)",
                origin: .dynamic,
                lastSeen: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let retained = ManagedRoutePolicy.retainedDynamicRoutes(
            routes,
            now: Date(timeIntervalSince1970: TimeInterval(routes.count))
        )

        XCTAssertEqual(retained.count, ManagedRoutePolicy.maxDynamicRoutes)
        XCTAssertEqual(retained.first?.identity.target, "198.51.100.521")
        XCTAssertEqual(retained.last?.identity.target, "198.51.100.10")
    }

    func testConfiguredAndPublicDNSRoutesNeverExpireThroughDynamicPolicy() {
        let old = Date(timeIntervalSince1970: 0)
        let records = [
            route("8.8.8.8", origin: .publicDNS, lastSeen: old),
            route("203.0.113.1", origin: .configured, lastSeen: old)
        ]

        XCTAssertEqual(
            ManagedRoutePolicy.retainedDynamicRoutes(
                records,
                now: Date(timeIntervalSince1970: 100_000)
            ),
            records
        )
    }

    func testLegacyFlatRouteRecordDecodesSafely() throws {
        let record = try JSONDecoder().decode(
            ManagedRouteRecord.self,
            from: Data(#"{"target":"203.0.113.1","network":true}"#.utf8)
        )

        XCTAssertEqual(record.identity, ManagedRouteIdentity(target: "203.0.113.1", network: true))
        XCTAssertEqual(record.origin, .legacy)
        XCTAssertEqual(record.lastSeen, .distantPast)
    }

    func testCleanupValuesAreChunkedAtConfiguredSize() {
        let chunks = ManagedRoutePolicy.chunks(
            Array(0..<130),
            size: ManagedRoutePolicy.cleanupChunkSize
        )

        XCTAssertEqual(chunks.map(\.count), [64, 64, 2])
    }

    func testResolverRestoreUsesBoundedParallelism() {
        XCTAssertEqual(ManagedRoutePolicy.resolverRestoreConcurrency, 8)
        XCTAssertGreaterThan(ManagedRoutePolicy.resolverRestoreConcurrency, 1)
        XCTAssertLessThanOrEqual(
            ManagedRoutePolicy.resolverRestoreConcurrency,
            ManagedRoutePolicy.cleanupConcurrency
        )
    }

    func testCleanupPlanPrioritizesPublicDNSRoutes() {
        let now = Date(timeIntervalSince1970: 1_000)
        let critical = route("8.8.8.8", origin: .publicDNS, lastSeen: now)
        let configured = route("203.0.113.1", origin: .configured, lastSeen: now)
        let dynamic = route("198.51.100.1", origin: .dynamic, lastSeen: now)

        let plan = ManagedRoutePolicy.cleanupPlan(for: [configured, critical, dynamic])

        XCTAssertEqual(plan.critical, [critical])
        XCTAssertEqual(plan.remainingChunks.flatMap { $0 }, [configured, dynamic])
        XCTAssertEqual(
            Set(plan.critical + plan.remainingChunks.flatMap { $0 }),
            Set([critical, configured, dynamic])
        )
    }
}
