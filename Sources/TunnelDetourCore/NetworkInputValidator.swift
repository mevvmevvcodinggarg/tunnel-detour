import Foundation

public enum NetworkInputValidator {
    public static func isInterface(_ value: String) -> Bool {
        (1...32).contains(value.count) && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber)
        }
    }

    public static func isDomain(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = RouteManager.normalizeHost(candidate)
        guard host == candidate, host.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        return labels.allSatisfy { label in
            guard (1...63).contains(label.count),
                  let first = label.first,
                  let last = label.last else { return false }
            let isASCIIAlphanumeric: (Character) -> Bool = {
                $0.isASCII && ($0.isLetter || $0.isNumber)
            }
            return isASCIIAlphanumeric(first)
                && isASCIIAlphanumeric(last)
                && label.allSatisfy { isASCIIAlphanumeric($0) || $0 == "-" }
        }
    }

    public static func isIPv4OrDomain(_ value: String) -> Bool {
        RouteManager.isIPv4(value) || isDomain(value)
    }

    public static func isCIDR(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              RouteManager.isIPv4(String(parts[0])),
              let prefix = Int(parts[1]) else { return false }
        return (0...32).contains(prefix)
    }
}
