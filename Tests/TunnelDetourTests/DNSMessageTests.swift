import XCTest
@testable import TunnelDetourCore

final class DNSMessageTests: XCTestCase {
    func testParsesAAAAQueryType() throws {
        let packet = DNSMessageTests.queryPacket(id: 0xabcd, host: "www.youtube.com", type: 28)

        let message = try DNSMessage.parse(packet)

        XCTAssertEqual(message.queryNames, ["www.youtube.com"])
        XCTAssertEqual(message.queryTypes, [28])
    }

    func testBuildsEmptyAnswerResponseForAAAAQuery() throws {
        let packet = DNSMessageTests.queryPacket(id: 0xabcd, host: "www.youtube.com", type: 28)

        let response = try DNSMessage.emptyAnswerResponse(for: packet)
        let bytes = [UInt8](response)

        XCTAssertEqual(bytes[0], 0xab)
        XCTAssertEqual(bytes[1], 0xcd)
        XCTAssertEqual(bytes[2] & 0x80, 0x80)
        XCTAssertEqual(bytes[3] & 0x0f, 0x00)
        XCTAssertEqual(bytes[4], 0x00)
        XCTAssertEqual(bytes[5], 0x01)
        XCTAssertEqual(bytes[6], 0x00)
        XCTAssertEqual(bytes[7], 0x00)
        XCTAssertEqual(bytes[8], 0x00)
        XCTAssertEqual(bytes[9], 0x00)
        XCTAssertEqual(bytes[10], 0x00)
        XCTAssertEqual(bytes[11], 0x00)
        XCTAssertEqual(try DNSMessage.parse(response).queryTypes, [28])
    }

    func testParsesCompressedAResponse() throws {
        let packet = Data([
            0x12, 0x34, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x03, 0x77, 0x77, 0x77,
            0x06, 0x67, 0x6f, 0x6f, 0x67, 0x6c, 0x65,
            0x03, 0x63, 0x6f, 0x6d, 0x00,
            0x00, 0x01, 0x00, 0x01,
            0xc0, 0x0c, 0x00, 0x01, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x3c, 0x00, 0x04,
            0x01, 0x02, 0x03, 0x04
        ])

        let message = try DNSMessage.parse(packet)

        XCTAssertEqual(message.queryNames, ["www.google.com"])
        XCTAssertEqual(message.ipv4Answers, ["1.2.3.4"])
    }

    func testSuffixAuthorizationUsesLabelBoundary() {
        XCTAssertTrue(DNSAuthorization.isAllowed(queryNames: ["files.slack.com"], suffixes: ["slack.com"]))
        XCTAssertFalse(DNSAuthorization.isAllowed(queryNames: ["evilslack.com"], suffixes: ["slack.com"]))
    }

    private static func queryPacket(id: UInt16, host: String, type: UInt16) -> Data {
        var bytes: [UInt8] = [
            UInt8(id >> 8), UInt8(id & 0xff),
            0x01, 0x00,
            0x00, 0x01,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00
        ]
        for label in host.split(separator: ".") {
            bytes.append(UInt8(label.utf8.count))
            bytes.append(contentsOf: label.utf8)
        }
        bytes.append(0x00)
        bytes.append(UInt8(type >> 8))
        bytes.append(UInt8(type & 0xff))
        bytes.append(0x00)
        bytes.append(0x01)
        return Data(bytes)
    }
}
