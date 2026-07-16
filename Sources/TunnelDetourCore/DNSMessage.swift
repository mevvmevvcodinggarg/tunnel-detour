import Foundation

public enum DNSMessageError: Error {
    case malformed
}

public struct DNSMessage: Equatable {
    public let queryNames: [String]
    public let queryTypes: [UInt16]
    public let ipv4Answers: [String]

    public static func parse(_ data: Data) throws -> DNSMessage {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { throw DNSMessageError.malformed }
        let questionCount = Int(readUInt16(bytes, 4))
        let answerCount = Int(readUInt16(bytes, 6))
        var offset = 12
        var queryNames: [String] = []
        var queryTypes: [UInt16] = []

        for _ in 0..<questionCount {
            queryNames.append(try readName(bytes, offset: &offset))
            guard offset + 4 <= bytes.count else { throw DNSMessageError.malformed }
            queryTypes.append(readUInt16(bytes, offset))
            offset += 4
        }

        var answers: [String] = []
        for _ in 0..<answerCount {
            _ = try readName(bytes, offset: &offset)
            guard offset + 10 <= bytes.count else { throw DNSMessageError.malformed }
            let type = readUInt16(bytes, offset)
            let recordClass = readUInt16(bytes, offset + 2)
            let length = Int(readUInt16(bytes, offset + 8))
            offset += 10
            guard offset + length <= bytes.count else { throw DNSMessageError.malformed }
            if type == 1, recordClass == 1, length == 4 {
                answers.append(bytes[offset..<(offset + 4)].map(String.init).joined(separator: "."))
            }
            offset += length
        }

        return DNSMessage(queryNames: queryNames, queryTypes: queryTypes, ipv4Answers: Array(Set(answers)).sorted())
    }

    public static func emptyAnswerResponse(for query: Data) throws -> Data {
        let bytes = [UInt8](query)
        guard bytes.count >= 12 else { throw DNSMessageError.malformed }
        let questionCount = Int(readUInt16(bytes, 4))
        var offset = 12

        for _ in 0..<questionCount {
            _ = try readName(bytes, offset: &offset)
            guard offset + 4 <= bytes.count else { throw DNSMessageError.malformed }
            offset += 4
        }

        var response = Array(bytes[0..<offset])
        let queryFlags = readUInt16(bytes, 2)
        let flags = UInt16(0x8000) | (queryFlags & 0x0100) | 0x0080
        response[2] = UInt8(flags >> 8)
        response[3] = UInt8(flags & 0xff)
        response[6] = 0x00
        response[7] = 0x00
        response[8] = 0x00
        response[9] = 0x00
        response[10] = 0x00
        response[11] = 0x00
        return Data(response)
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func readName(_ bytes: [UInt8], offset: inout Int) throws -> String {
        var cursor = offset
        var returnOffset: Int?
        var labels: [String] = []
        var hops = 0

        while true {
            guard cursor < bytes.count, hops < 64 else { throw DNSMessageError.malformed }
            hops += 1
            let length = Int(bytes[cursor])
            if length == 0 {
                cursor += 1
                offset = returnOffset ?? cursor
                return labels.joined(separator: ".").lowercased()
            }
            if length & 0xc0 == 0xc0 {
                guard cursor + 1 < bytes.count else { throw DNSMessageError.malformed }
                let pointer = ((length & 0x3f) << 8) | Int(bytes[cursor + 1])
                guard pointer < bytes.count else { throw DNSMessageError.malformed }
                returnOffset = returnOffset ?? (cursor + 2)
                cursor = pointer
                continue
            }
            guard length <= 63, cursor + 1 + length <= bytes.count else {
                throw DNSMessageError.malformed
            }
            let labelBytes = bytes[(cursor + 1)..<(cursor + 1 + length)]
            guard let label = String(bytes: labelBytes, encoding: .utf8) else {
                throw DNSMessageError.malformed
            }
            labels.append(label)
            cursor += 1 + length
        }
    }
}

public enum DNSAuthorization {
    public static func isAllowed(queryNames: [String], suffixes: [String]) -> Bool {
        queryNames.contains { rawQuery in
            let query = rawQuery.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return suffixes.contains { rawSuffix in
                let suffix = rawSuffix.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return query == suffix || query.hasSuffix("." + suffix)
            }
        }
    }
}
