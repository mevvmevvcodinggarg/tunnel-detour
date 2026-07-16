import XCTest
@testable import TunnelDetourCore

final class ActivityMessageTests: XCTestCase {
    func testFailureMessageDoesNotExposeTechnicalDetails() {
        let error = RouteManagerError.commandFailed(
            "/sbin/route add 142.250.0.0/15 via 192.168.66.1 interface en0 /etc/resolver/google.com"
        )

        let message = ActivityMessage.failure(for: error)

        XCTAssertEqual(message, "Operation failed.")
        for forbidden in ["route", "142.250", "192.168", "en0", "resolver", "google.com"] {
            XCTAssertFalse(message.localizedCaseInsensitiveContains(forbidden))
        }
    }

    func testTimeoutFailureIsActionableButGeneric() {
        XCTAssertEqual(
            ActivityMessage.failure(for: AdaptiveControllerError.timedOut),
            "Operation timed out."
        )
    }

    func testActivityMessagesUseGenericWording() {
        let messages = [
            ActivityMessage.ready,
            ActivityMessage.saved,
            ActivityMessage.restored,
            ActivityMessage.applying,
            ActivityMessage.applied,
            ActivityMessage.checking,
            ActivityMessage.checked,
            ActivityMessage.repairing,
            ActivityMessage.repaired,
            ActivityMessage.restoring,
            ActivityMessage.restoredSystem,
            ActivityMessage.removingHelper,
            ActivityMessage.removedHelper
        ]

        for message in messages {
            for forbidden in ["route", "gateway", "interface", "domain", "dns", "vpn", "wifi"] {
                XCTAssertFalse(message.localizedCaseInsensitiveContains(forbidden))
            }
        }
    }
}
