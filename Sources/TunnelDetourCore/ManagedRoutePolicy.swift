import Foundation

public enum NetworkTransitionAction: Equatable {
    case enterFailOpen
    case reapply
}

public enum ManagedRouteOrigin: String, Codable, Equatable, Hashable {
    case publicDNS
    case configured
    case dynamic
    case legacy
}

public struct ManagedRouteIdentity: Codable, Equatable, Hashable {
    public let target: String
    public let network: Bool

    public init(target: String, network: Bool) {
        self.target = target
        self.network = network
    }
}

public struct ManagedRouteRecord: Codable, Equatable, Hashable {
    public let identity: ManagedRouteIdentity
    public var origin: ManagedRouteOrigin
    public var lastSeen: Date

    public init(
        identity: ManagedRouteIdentity,
        origin: ManagedRouteOrigin,
        lastSeen: Date
    ) {
        self.identity = identity
        self.origin = origin
        self.lastSeen = lastSeen
    }

    private enum CodingKeys: String, CodingKey {
        case identity
        case origin
        case lastSeen
        case target
        case network
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let identity = try container.decodeIfPresent(ManagedRouteIdentity.self, forKey: .identity) {
            self.identity = identity
        } else {
            self.identity = ManagedRouteIdentity(
                target: try container.decode(String.self, forKey: .target),
                network: try container.decode(Bool.self, forKey: .network)
            )
        }
        origin = try container.decodeIfPresent(ManagedRouteOrigin.self, forKey: .origin) ?? .legacy
        lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen) ?? .distantPast
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identity, forKey: .identity)
        try container.encode(origin, forKey: .origin)
        try container.encode(lastSeen, forKey: .lastSeen)
    }
}

public struct RouteCleanupPlan: Equatable {
    public let critical: [ManagedRouteRecord]
    public let remainingChunks: [[ManagedRouteRecord]]

    public init(critical: [ManagedRouteRecord], remainingChunks: [[ManagedRouteRecord]]) {
        self.critical = critical
        self.remainingChunks = remainingChunks
    }
}

public enum ManagedRoutePolicy {
    public static let dynamicRouteTTL: TimeInterval = 6 * 60 * 60
    public static let maxDynamicRoutes = 512
    public static let cleanupConcurrency = 8
    public static let resolverRestoreConcurrency = 8
    public static let cleanupChunkSize = 64
    public static let networkDebounce: TimeInterval = 1.5
    public static let gatewayWatchInterval: TimeInterval = 5
    public static let dynamicStateSaveDebounce: TimeInterval = 0.5

    public static func transitionActions(
        previousGateway: String?,
        observedGateway: String?,
        hasActiveRequest: Bool
    ) -> [NetworkTransitionAction] {
        guard hasActiveRequest else { return [] }
        guard let observedGateway else { return [.enterFailOpen] }
        guard previousGateway != observedGateway else { return [] }

        switch previousGateway {
        case .some:
            return [.enterFailOpen, .reapply]
        case .none:
            return [.reapply]
        }
    }

    public static func retainedDynamicRoutes(
        _ records: [ManagedRouteRecord],
        now: Date = Date()
    ) -> [ManagedRouteRecord] {
        let stable = records.filter { $0.origin != .dynamic }
        let cutoff = now.addingTimeInterval(-dynamicRouteTTL)
        let dynamic = records
            .filter { $0.origin == .dynamic && $0.lastSeen >= cutoff }
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(maxDynamicRoutes)
        return stable + dynamic
    }

    public static func chunks<T>(_ values: [T], size: Int) -> [[T]] {
        precondition(size > 0)
        return stride(from: 0, to: values.count, by: size).map { start in
            Array(values[start..<min(start + size, values.count)])
        }
    }

    public static func cleanupPlan(for records: [ManagedRouteRecord]) -> RouteCleanupPlan {
        let critical = records.filter { $0.origin == .publicDNS }
        let remaining = records.filter { $0.origin != .publicDNS }
        return RouteCleanupPlan(
            critical: critical,
            remainingChunks: chunks(remaining, size: cleanupChunkSize)
        )
    }
}
