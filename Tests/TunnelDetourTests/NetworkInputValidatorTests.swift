import XCTest
@testable import TunnelDetourCore

final class NetworkInputValidatorTests: XCTestCase {
    func testAcceptsNormalNetworkInputs() {
        XCTAssertTrue(NetworkInputValidator.isInterface("en0"))
        XCTAssertTrue(NetworkInputValidator.isInterface("bridge100"))
        XCTAssertTrue(NetworkInputValidator.isDomain("mail.example.com"))
        XCTAssertTrue(NetworkInputValidator.isIPv4OrDomain("203.0.113.10"))
        XCTAssertTrue(NetworkInputValidator.isCIDR("203.0.113.0/24"))
    }

    func testRejectsMalformedInterfaces() {
        ["", "en0;id", "en 0", "../../tmp"].forEach {
            XCTAssertFalse(NetworkInputValidator.isInterface($0), $0)
        }
    }

    func testRejectsMalformedDomains() {
        ["", "localhost", "-bad.example", "bad..example", "bad.example-", "a/b.example"].forEach {
            XCTAssertFalse(NetworkInputValidator.isDomain($0), $0)
        }
    }

    func testRejectsMalformedCIDRs() {
        ["203.0.113.0/-1", "203.0.113.0/33", "999.1.1.1/24", "203.0.113.0;x/24"].forEach {
            XCTAssertFalse(NetworkInputValidator.isCIDR($0), $0)
        }
    }
}
