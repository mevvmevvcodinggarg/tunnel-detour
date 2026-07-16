import Foundation
import Network
import TunnelDetourCore
import Darwin

private struct RouteRecord: Codable, Hashable {
    let target: String
    let network: Bool
}

private struct ResolverBackup: Codable {
    let existed: Bool
    let contents: Data?
}

private struct HelperState: Codable {
    var routes: Set<RouteRecord> = []
    var resolvers: [String: ResolverBackup] = [:]
}

final class SystemController {
    private let stateURL = URL(fileURLWithPath: AdaptiveArtifacts.statePath)
    private let queue = DispatchQueue(label: "io.github.mevvmevvcodinggarg.tunneldetour.system-state")
    private var state = HelperState()
    private var wifiInterface = "en0"

    init() {
        if let data = try? Data(contentsOf: stateURL),
           let decoded = try? JSONDecoder().decode(HelperState.self, from: data) {
            state = decoded
        }
    }

    func apply(_ request: AdaptiveRequest) throws {
        try queue.sync {
            try validate(request)
            wifiInterface = request.wifiInterface
            if AdaptiveBehavior.shouldPruneExistingRoutesDuringApply {
                try removeManagedRoutes()
            }
            let gateway = try currentGateway()

            for dns in request.publicDNS { try addRoute(dns, network: false, gateway: gateway) }
            for cidr in request.directCIDRs { try addRoute(cidr, network: true, gateway: gateway) }
            for ip in request.ipv4Targets { try addRoute(ip, network: false, gateway: gateway) }

            if AdaptiveBehavior.shouldPreResolveDomains(adaptiveEnabled: request.adaptiveEnabled) {
                for ip in resolveAll(request.domainTargets, dnsServers: request.publicDNS) {
                    try addRoute(ip, network: false, gateway: gateway)
                }
            }

            var resolverChanged = false
            for domain in request.resolverDomains {
                try snapshotResolver(domain)
                let contents: String
                if request.adaptiveEnabled {
                    contents = AdaptiveResolverPolicy.ownedContents
                } else {
                    contents = request.publicDNS.map { "nameserver \($0)" }.joined(separator: "\n") + "\n"
                }
                resolverChanged = try writeResolver(domain, contents: contents) || resolverChanged
            }
            if resolverChanged {
                flushDNS()
            }
            try saveState()
        }
    }

    func repair(_ request: AdaptiveRequest) throws {
        try queue.sync {
            try validate(request)
            wifiInterface = request.wifiInterface
            let gateway = try currentGateway()
            guard let target = request.repairTarget,
                  NetworkInputValidator.isIPv4OrDomain(target) else {
                throw NSError(domain: ProductIdentity.bundleIdentifier, code: 2)
            }
            let values = RouteManager.isIPv4(target)
                ? [target]
                : resolve(target, dnsServers: request.publicDNS)
            guard !values.isEmpty else { throw NSError(domain: ProductIdentity.bundleIdentifier, code: 3) }
            for ip in values { try addRoute(ip, network: false, gateway: gateway) }
            try saveState()
        }
    }

    func routeDynamic(_ addresses: [String]) {
        queue.sync {
            let newAddresses = addresses
                .filter(RouteManager.isIPv4)
                .filter { ip in
                    AdaptiveBehavior.shouldRefreshManagedRoute(
                        alreadyManaged: state.routes.contains(RouteRecord(target: ip, network: false)),
                        force: false
                    )
                }
            guard !newAddresses.isEmpty else { return }
            guard let gateway = try? currentGateway() else { return }
            for ip in newAddresses {
                try? addRoute(ip, network: false, gateway: gateway, force: false)
            }
            try? saveState()
        }
    }

    func restore() throws {
        try queue.sync {
            try removeManagedRoutes()
            for (domain, backup) in state.resolvers {
                let url = URL(fileURLWithPath: "/etc/resolver/\(domain)")
                if backup.existed, let contents = backup.contents {
                    try contents.write(to: url, options: .atomic)
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            try removeOrphanedResolvers()
            state = HelperState()
            flushDNS()
            try saveState()
        }
    }

    private func removeOrphanedResolvers() throws {
        let directory = URL(fileURLWithPath: "/etc/resolver", isDirectory: true)
        for file in try AdaptiveResolverPolicy.ownedResolverURLs(in: directory) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func validate(_ request: AdaptiveRequest) throws {
        guard NetworkInputValidator.isInterface(request.wifiInterface),
              request.publicDNS.allSatisfy(RouteManager.isIPv4),
              request.ipv4Targets.allSatisfy(RouteManager.isIPv4),
              request.domainTargets.allSatisfy(NetworkInputValidator.isDomain),
              request.resolverDomains.allSatisfy(NetworkInputValidator.isDomain),
              request.directCIDRs.allSatisfy(NetworkInputValidator.isCIDR) else {
            throw NSError(domain: ProductIdentity.bundleIdentifier, code: 1)
        }
    }

    private func currentGateway() throws -> String {
        let result = try run("/usr/sbin/ipconfig", ["getoption", wifiInterface, "router"])
        let gateway = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RouteManager.isIPv4(gateway) else {
            throw NSError(domain: ProductIdentity.bundleIdentifier, code: 4)
        }
        return gateway
    }

    private func resolve(_ domain: String, dnsServers: [String]) -> [String] {
        var values = Set<String>()
        for dns in dnsServers {
            if let output = try? run("/usr/bin/dig", ["@\(dns)", "+time=1", "+tries=1", "+short", "A", domain]) {
                output.split(whereSeparator: \.isNewline).map(String.init)
                    .filter(RouteManager.isIPv4).forEach { values.insert($0) }
            }
        }
        return values.sorted()
    }

    private func resolveAll(_ domains: [String], dnsServers: [String]) -> [String] {
        let operations = OperationQueue()
        operations.maxConcurrentOperationCount = 24
        let lock = NSLock()
        var values = Set<String>()

        for domain in domains {
            operations.addOperation { [weak self] in
                guard let self else { return }
                var resolved: [String] = []
                for dns in dnsServers {
                    resolved = self.resolve(domain, dnsServers: [dns])
                    if !resolved.isEmpty { break }
                }
                lock.lock()
                values.formUnion(resolved)
                lock.unlock()
            }
        }
        operations.waitUntilAllOperationsAreFinished()
        return values.sorted()
    }

    private func addRoute(_ target: String, network: Bool, gateway: String, force: Bool = true) throws {
        let record = RouteRecord(target: target, network: network)
        guard AdaptiveBehavior.shouldRefreshManagedRoute(
            alreadyManaged: state.routes.contains(record),
            force: force
        ) else { return }
        state.routes.insert(record)
        let kind = network ? "-net" : "-host"
        _ = try? run("/sbin/route", ["-n", "delete", kind, target])
        _ = try run("/sbin/route", ["-n", "add", kind, target, gateway])
    }

    private func removeManagedRoutes() throws {
        for route in state.routes {
            let kind = route.network ? "-net" : "-host"
            _ = try? run("/sbin/route", ["-n", "delete", kind, route.target])
        }
        state.routes.removeAll()
    }

    private func snapshotResolver(_ domain: String) throws {
        guard state.resolvers[domain] == nil else { return }
        let url = URL(fileURLWithPath: "/etc/resolver/\(domain)")
        let data = try? Data(contentsOf: url)
        state.resolvers[domain] = ResolverBackup(existed: data != nil, contents: data)
    }

    private func writeResolver(_ domain: String, contents: String) throws -> Bool {
        let url = URL(fileURLWithPath: "/etc/resolver/\(domain)")
        let existing = try? Data(contentsOf: url)
        guard AdaptiveBehavior.shouldWriteResolver(
            existingContents: existing,
            desiredContents: contents
        ) else { return false }

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: "/etc/resolver"),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(
            to: url,
            options: .atomic
        )
        return true
    }

    private func saveState() throws {
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    private func flushDNS() {
        _ = try? run("/usr/bin/dscacheutil", ["-flushcache"])
        _ = try? run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }

    @discardableResult private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: ProductIdentity.bundleIdentifier, code: Int(process.terminationStatus))
        }
        return output
    }
}

final class DNSRelay {
    private var listener: NWListener?
    private let controller: SystemController
    private var suffixes: [String] = []
    private var dnsServers: [String] = []

    init(controller: SystemController) { self.controller = controller }

    func configure(enabled: Bool, suffixes: [String], dnsServers: [String]) throws {
        self.suffixes = suffixes
        self.dnsServers = dnsServers
        if enabled, listener == nil {
            let parameters = NWParameters.udp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 55353)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global(qos: .utility))
                self?.receive(on: connection)
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        } else if !enabled {
            listener?.cancel()
            listener = nil
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil, let data else { connection.cancel(); return }
            self.forward(data, client: connection)
        }
    }

    private func forward(_ query: Data, client: NWConnection) {
        guard let parsedQuery = try? DNSMessage.parse(query),
              DNSAuthorization.isAllowed(queryNames: parsedQuery.queryNames, suffixes: suffixes) else {
            client.cancel()
            return
        }
        if AdaptiveBehavior.shouldSuppressIPv6ForDirectDomains,
           parsedQuery.queryTypes.contains(28),
           let response = try? DNSMessage.emptyAnswerResponse(for: query) {
            client.send(content: response, completion: .contentProcessed { _ in
                client.cancel()
            })
            return
        }
        guard let dns = dnsServers.first else {
            client.cancel()
            return
        }

        let upstream = NWConnection(host: NWEndpoint.Host(dns), port: 53, using: .udp)
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                upstream.send(content: query, completion: .contentProcessed { error in
                    guard error == nil else {
                        upstream.cancel()
                        client.cancel()
                        return
                    }
                    upstream.receiveMessage { data, _, _, _ in
                        defer { upstream.cancel() }
                        guard let data else {
                            client.cancel()
                            return
                        }
                        let addresses = (try? DNSMessage.parse(data))?.ipv4Answers ?? []
                        client.send(content: data, completion: .contentProcessed { _ in
                            client.cancel()
                            guard AdaptiveBehavior.shouldReplyBeforeDynamicRouting,
                                  !addresses.isEmpty else { return }
                            DispatchQueue.global(qos: .utility).async {
                                self.controller.routeDynamic(addresses)
                            }
                        })
                    }
                })
            }
        }
        upstream.start(queue: .global(qos: .utility))
    }
}

private let arguments = CommandLine.arguments
guard arguments.count == 3 else { exit(64) }
let requestURL = URL(fileURLWithPath: arguments[1])
let responseURL = URL(fileURLWithPath: arguments[2])
let controller = SystemController()
let relay = DNSRelay(controller: controller)
var lastID = ""

while true {
    autoreleasepool {
        guard let data = try? Data(contentsOf: requestURL),
              let request = try? JSONDecoder().decode(AdaptiveRequest.self, from: data),
              request.id != lastID else { return }
        lastID = request.id
        var success = false
        do {
            switch request.action {
            case .apply:
                try relay.configure(
                    enabled: request.adaptiveEnabled,
                    suffixes: request.resolverDomains,
                    dnsServers: request.publicDNS
                )
                do {
                    try controller.apply(request)
                } catch {
                    try? relay.configure(enabled: false, suffixes: [], dnsServers: [])
                    throw error
                }
            case .repair:
                try controller.repair(request)
            case .restore:
                try relay.configure(enabled: false, suffixes: [], dnsServers: [])
                try controller.restore()
            }
            success = true
        } catch {}
        let response = AdaptiveResponse(id: request.id, success: success)
        if let responseData = try? JSONEncoder().encode(response) {
            let requestAttributes = try? FileManager.default.attributesOfItem(atPath: requestURL.path)
            try? responseData.write(to: responseURL, options: .atomic)
            if let owner = requestAttributes?[.ownerAccountID] as? NSNumber,
               let group = requestAttributes?[.groupOwnerAccountID] as? NSNumber {
                _ = chown(responseURL.path, owner.uint32Value, group.uint32Value)
            }
            _ = chmod(responseURL.path, S_IRUSR | S_IWUSR)
        }
    }
    Thread.sleep(forTimeInterval: 0.25)
}
