import XCTest
@testable import TunnelDetourCore

final class SiteRouteStateTests: XCTestCase {
    func testClassifiesDirectRouteInterfaces() {
        XCTAssertEqual(
            RouteManager.classifyRouteInterfaces(["en0", "en0"], directInterface: "en0"),
            .direct
        )
    }

    func testClassifiesPrivateAndMixedRouteInterfaces() {
        XCTAssertEqual(
            RouteManager.classifyRouteInterfaces(["utun4"], directInterface: "en0"),
            .privatePath
        )
        XCTAssertEqual(
            RouteManager.classifyRouteInterfaces(["en0", "utun4"], directInterface: "en0"),
            .mixed
        )
    }

    func testClassifiesEmptyRouteResultAsUnavailable() {
        XCTAssertEqual(
            RouteManager.classifyRouteInterfaces([], directInterface: "en0"),
            .unavailable
        )
    }

    func testFindsURLHostInConfiguredDirectSites() {
        XCTAssertTrue(RouteManager.isConfiguredSite(
            "https://www.youtube.com/watch?v=example",
            config: .defaults
        ))
        XCTAssertFalse(RouteManager.isConfiguredSite(
            "https://not-configured.invalid/path",
            config: .defaults
        ))
    }

    func testCreatesQuickAddTargetFromURLOrIPv4() {
        XCTAssertEqual(
            RouteManager.directTarget(for: "https://example.com/path"),
            RouteTarget(kind: .domain, value: "example.com")
        )
        XCTAssertEqual(
            RouteManager.directTarget(for: "203.0.113.10"),
            RouteTarget(kind: .ipv4, value: "203.0.113.10")
        )
        XCTAssertNil(RouteManager.directTarget(for: "   "))
    }

    func testDisplayTextDoesNotExposeTechnicalRouteTerms() {
        XCTAssertEqual(SiteRouteState.direct.displayText, "Direct")
        XCTAssertEqual(SiteRouteState.privatePath.displayText, "Private path")
        XCTAssertEqual(SiteRouteState.mixed.displayText, "Mixed")
        XCTAssertEqual(SiteRouteState.unavailable.displayText, "Unavailable")
    }
}
