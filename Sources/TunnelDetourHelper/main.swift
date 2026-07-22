import Foundation
import Network
import TunnelDetourCore
import Darwin

private struct ResolverBackup: Codable {
    let existed: Bool
    let contents: Data?
}

private struct HelperState: Codable {
    var routes: [ManagedRouteRecord] = []
    var resolvers: [String: ResolverBackup] = [:]
    var activeRequest: AdaptiveRequest?
    var activeGateway: String?
    var isFailOpen = false

    private enum CodingKeys: String, CodingKey {
        case routes
        case resolvers
        case activeRequest
        case activeGateway
        case isFailOpen
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routes = try container.decodeIfPresent([ManagedRouteRecord].self, forKey: .routes) ?? []
        resolvers = try container.decodeIfPresent([String: ResolverBackup].self, forKey: .resolvers) ?? [:]
        activeRequest = try container.decodeIfPresent(AdaptiveRequest.self, forKey: .activeRequest)
        activeGateway = try container.decodeIfPresent(String.self, forKey: .activeGateway)
        isFailOpen = try container.decodeIfPresent(Bool.self, forKey: .isFailOpen) ?? false
    }
}

final class SystemController {
    private let stateURL = URL(fileURLWithPath: AdaptiveArtifacts.statePath)
    private let queue = DispatchQueue(label: "io.github.mevvmevvcodinggarg.tunneldetour.system-state")
    private var state = HelperState()
    private var wifiInterface = "en0"
    private var pendingStateSave: DispatchWorkItem?

    init() {
        if let data = try? Data(contentsOf: stateURL),
           let decoded = try? JSONDecoder().decode(HelperState.self, from: data) {
            state = decoded
            wifiInterface = decoded.activeRequest?.wifiInterface ?? wifiInterface
        }
    }

    func apply(_ request: AdaptiveRequest) throws {
        try queue.sync {
            try validate(request)
            wifiInterface = request.wifiInterface
            let gateway = try currentGateway()
            try applyLocked(request, gateway: gateway)
        }
    }

    func hasActiveRequest() -> Bool {
        queue.sync { state.activeRequest != nil }
    }

    func reconciliationSnapshot() -> (
        previousGateway: String?,
        observedGateway: String?,
        hasActiveRequest: Bool
    ) {
        queue.sync {
            guard let request = state.activeRequest else {
                return (state.activeGateway, nil, false)
            }
            wifiInterface = request.wifiInterface
            return (state.activeGateway, try? currentGateway(), true)
        }
    }

    func enterFailOpen() throws {
        try queue.sync {
            let hasActiveRequest = state.activeRequest != nil
            guard hasActiveRequest || !state.routes.isEmpty || !state.resolvers.isEmpty else { return }
            guard !state.isFailOpen else { return }
            cancelPendingStateSave()
            try restoreResolvers(retainingBackups: hasActiveRequest)
            let critical = state.routes.filter { $0.origin == .publicDNS }
            deleteRoutesSequentially(critical)
            let criticalIdentities = Set(critical.map(\.identity))
            state.routes.removeAll { criticalIdentities.contains($0.identity) }
            if !hasActiveRequest {
                deleteRoutesConcurrently(state.routes)
                state = HelperState()
                flushDNS()
                try saveState()
                return
            }
            state.activeGateway = nil
            state.isFailOpen = true
            flushDNS()
            try saveState()
        }
    }

    func reapplyActiveRequest(gateway: String) throws -> AdaptiveRequest {
        try queue.sync {
            guard let request = state.activeRequest, RouteManager.isIPv4(gateway) else {
                throw NSError(domain: ProductIdentity.bundleIdentifier, code: 5)
            }
            cancelPendingStateSave()
            state.isFailOpen = false
            try saveState()

            let stale = state.routes.filter { $0.origin == .legacy || $0.origin == .dynamic }
            deleteRoutesConcurrently(stale)
            let staleIdentities = Set(stale.map(\.identity))
            state.routes.removeAll { staleIdentities.contains($0.identity) }
            wifiInterface = request.wifiInterface
            try applyLocked(request, gateway: gateway)
            return request
        }
    }

    func repair(_ request: AdaptiveRequest) throws {
        try queue.sync {
            try validate(request)
            cancelPendingStateSave()
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
            for ip in values {
                try addRoute(ip, network: false, gateway: gateway, origin: .configured)
            }
            try saveState()
        }
    }

    func routeDynamic(_ addresses: [String]) {
        queue.sync {
            let validAddresses = Array(Set(addresses.filter(RouteManager.isIPv4))).sorted()
            guard !validAddresses.isEmpty, let gateway = state.activeGateway else { return }
            let now = Date()
            pruneDynamicRoutes(now: now)
            for ip in validAddresses {
                try? addRoute(
                    ip,
                    network: false,
                    gateway: gateway,
                    origin: .dynamic,
                    force: false,
                    now: now
                )
            }
            pruneDynamicRoutes(now: now)
            scheduleDynamicStateSave()
        }
    }

    func restore() throws {
        try queue.sync {
            cancelPendingStateSave()
            try restoreResolvers(retainingBackups: false)
            let plan = ManagedRoutePolicy.cleanupPlan(for: state.routes)
            deleteRoutesSequentially(plan.critical)
            flushDNS()
            for chunk in plan.remainingChunks {
                deleteRoutesConcurrently(chunk)
            }
            state = HelperState()
            try saveState()
        }
    }

    private func applyLocked(_ request: AdaptiveRequest, gateway: String) throws {
        cancelPendingStateSave()
        if AdaptiveBehavior.shouldPruneExistingRoutesDuringApply {
            try removeManagedRoutes()
        }
        let forceRefresh = state.activeGateway != gateway || state.isFailOpen

        for dns in request.publicDNS {
            try addRoute(
                dns,
                network: false,
                gateway: gateway,
                origin: .publicDNS,
                force: forceRefresh
            )
        }
        for cidr in request.directCIDRs {
            try addRoute(
                cidr,
                network: true,
                gateway: gateway,
                origin: .configured,
                force: forceRefresh
            )
        }
        for ip in request.ipv4Targets {
            try addRoute(
                ip,
                network: false,
                gateway: gateway,
                origin: .configured,
                force: forceRefresh
            )
        }

        if AdaptiveBehavior.shouldPreResolveDomains(adaptiveEnabled: request.adaptiveEnabled) {
            for ip in resolveAll(request.domainTargets, dnsServers: request.publicDNS) {
                try addRoute(
                    ip,
                    network: false,
                    gateway: gateway,
                    origin: .configured,
                    force: forceRefresh
                )
            }
        }

        if try writeResolvers(for: request) {
            flushDNS()
        }
        state.activeRequest = request
        state.activeGateway = gateway
        state.isFailOpen = false
        try saveState()
    }

    private func removeOrphanedResolvers() throws {
        let directory = URL(fileURLWithPath: "/etc/resolver", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try AdaptiveResolverPolicy.ownedResolverURLs(in: directory) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func restoreResolvers(retainingBackups: Bool) throws {
        let backups = state.resolvers
        if backups.values.contains(where: { $0.existed }) {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: "/etc/resolver", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let operations = OperationQueue()
        operations.maxConcurrentOperationCount = ManagedRoutePolicy.resolverRestoreConcurrency
        let errorLock = NSLock()
        var firstError: Error?
        for (domain, backup) in backups {
            operations.addOperation {
                do {
                    let url = URL(fileURLWithPath: "/etc/resolver/\(domain)")
                    if backup.existed, let contents = backup.contents {
                        try contents.write(to: url, options: .atomic)
                    } else {
                        try? FileManager.default.removeItem(at: url)
                    }
                } catch {
                    errorLock.lock()
                    if firstError == nil { firstError = error }
                    errorLock.unlock()
                }
            }
        }
        operations.waitUntilAllOperationsAreFinished()
        if let firstError { throw firstError }

        try removeOrphanedResolvers()
        if !retainingBackups {
            state.resolvers.removeAll()
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

    private func addRoute(
        _ target: String,
        network: Bool,
        gateway: String,
        origin: ManagedRouteOrigin,
        force: Bool = true,
        now: Date = Date()
    ) throws {
        let identity = ManagedRouteIdentity(target: target, network: network)
        if let index = state.routes.firstIndex(where: { $0.identity == identity }) {
            state.routes[index].lastSeen = now
            if origin != .dynamic || state.routes[index].origin == .dynamic || state.routes[index].origin == .legacy {
                state.routes[index].origin = origin
            }
            guard force else { return }
        }

        let kind = network ? "-net" : "-host"
        _ = try? run("/sbin/route", ["-n", "delete", kind, target])
        _ = try run("/sbin/route", ["-n", "add", kind, target, gateway])

        let record = ManagedRouteRecord(identity: identity, origin: origin, lastSeen: now)
        if let index = state.routes.firstIndex(where: { $0.identity == identity }) {
            state.routes[index] = record
        } else {
            state.routes.append(record)
        }
    }

    private func removeManagedRoutes() throws {
        let plan = ManagedRoutePolicy.cleanupPlan(for: state.routes)
        deleteRoutesSequentially(plan.critical)
        for chunk in plan.remainingChunks {
            deleteRoutesConcurrently(chunk)
        }
        state.routes.removeAll()
    }

    private func deleteRoutesSequentially(_ records: [ManagedRouteRecord]) {
        for record in records {
            deleteRoute(record)
        }
    }

    private func deleteRoutesConcurrently(_ records: [ManagedRouteRecord]) {
        guard !records.isEmpty else { return }
        let records = records
        let operations = OperationQueue()
        operations.maxConcurrentOperationCount = ManagedRoutePolicy.cleanupConcurrency
        for record in records {
            operations.addOperation { [weak self] in
                self?.deleteRoute(record)
            }
        }
        operations.waitUntilAllOperationsAreFinished()
    }

    private func deleteRoute(_ record: ManagedRouteRecord) {
        let kind = record.identity.network ? "-net" : "-host"
        _ = try? run("/sbin/route", ["-n", "delete", kind, record.identity.target])
    }

    private func pruneDynamicRoutes(now: Date) {
        let retained = ManagedRoutePolicy.retainedDynamicRoutes(state.routes, now: now)
        let retainedIdentities = Set(retained.map(\.identity))
        let evicted = state.routes.filter {
            $0.origin == .dynamic && !retainedIdentities.contains($0.identity)
        }
        deleteRoutesConcurrently(evicted)
        state.routes = retained
    }

    private func snapshotResolver(_ domain: String) throws {
        guard state.resolvers[domain] == nil else { return }
        let url = URL(fileURLWithPath: "/etc/resolver/\(domain)")
        let data = try? Data(contentsOf: url)
        state.resolvers[domain] = ResolverBackup(existed: data != nil, contents: data)
    }

    private func writeResolvers(for request: AdaptiveRequest) throws -> Bool {
        let contents: String
        if request.adaptiveEnabled {
            contents = AdaptiveResolverPolicy.ownedContents
        } else {
            contents = request.publicDNS.map { "nameserver \($0)" }.joined(separator: "\n") + "\n"
        }

        for domain in request.resolverDomains {
            try snapshotResolver(domain)
        }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: "/etc/resolver", isDirectory: true),
            withIntermediateDirectories: true
        )

        var changed = false
        for domain in request.resolverDomains {
            changed = try writeResolver(domain, contents: contents) || changed
        }
        return changed
    }

    private func writeResolver(_ domain: String, contents: String) throws -> Bool {
        let url = URL(fileURLWithPath: "/etc/resolver/\(domain)")
        let existing = try? Data(contentsOf: url)
        guard AdaptiveBehavior.shouldWriteResolver(
            existingContents: existing,
            desiredContents: contents
        ) else { return false }

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

    private func cancelPendingStateSave() {
        pendingStateSave?.cancel()
        pendingStateSave = nil
    }

    private func scheduleDynamicStateSave() {
        cancelPendingStateSave()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingStateSave = nil
            try? self.saveState()
        }
        pendingStateSave = workItem
        queue.asyncAfter(
            deadline: .now() + ManagedRoutePolicy.dynamicStateSaveDebounce,
            execute: workItem
        )
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
    private let lock = NSLock()

    init(controller: SystemController) { self.controller = controller }

    func configure(enabled: Bool, suffixes: [String], dnsServers: [String]) throws {
        lock.lock()
        defer { lock.unlock() }
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
        lock.lock()
        let suffixes = self.suffixes
        let dnsServers = self.dnsServers
        lock.unlock()

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

final class NetworkResilienceCoordinator {
    private let controller: SystemController
    private let relay: DNSRelay
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: "io.github.mevvmevvcodinggarg.tunneldetour.network-watch"
    )
    private var pending: DispatchWorkItem?
    private var watchdog: DispatchSourceTimer?
    private var requiresStartupRecovery = true

    init(controller: SystemController, relay: DNSRelay) {
        self.controller = controller
        self.relay = relay
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] _ in
            self?.scheduleReconciliation(after: ManagedRoutePolicy.networkDebounce)
        }
        monitor.start(queue: queue)
        queue.async { [weak self] in
            guard let self else { return }
            self.updateWatchdog()
            if self.controller.hasActiveRequest() {
                self.scheduleReconciliation(after: 0)
            }
        }
    }

    func requestStateDidChange() {
        queue.async { [weak self] in
            guard let self else { return }
            self.updateWatchdog()
            if self.controller.hasActiveRequest() {
                self.scheduleReconciliation(after: 0)
            } else {
                self.pending?.cancel()
                self.pending = nil
            }
        }
    }

    private func updateWatchdog() {
        let active = controller.hasActiveRequest()
        if active, watchdog == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now() + ManagedRoutePolicy.gatewayWatchInterval,
                repeating: ManagedRoutePolicy.gatewayWatchInterval
            )
            timer.setEventHandler { [weak self] in
                self?.scheduleReconciliation(after: 0)
            }
            timer.resume()
            watchdog = timer
        } else if !active, let watchdog {
            watchdog.cancel()
            self.watchdog = nil
        }
    }

    private func scheduleReconciliation(after delay: TimeInterval) {
        pending?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reconcile()
        }
        pending = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func reconcile() {
        pending = nil
        let snapshot = controller.reconciliationSnapshot()
        let previousGateway = requiresStartupRecovery && snapshot.hasActiveRequest
            ? nil
            : snapshot.previousGateway
        requiresStartupRecovery = false
        let actions = ManagedRoutePolicy.transitionActions(
            previousGateway: previousGateway,
            observedGateway: snapshot.observedGateway,
            hasActiveRequest: snapshot.hasActiveRequest
        )

        for action in actions {
            switch action {
            case .enterFailOpen:
                try? relay.configure(enabled: false, suffixes: [], dnsServers: [])
                try? controller.enterFailOpen()
            case .reapply:
                guard let gateway = snapshot.observedGateway else { continue }
                do {
                    let request = try controller.reapplyActiveRequest(gateway: gateway)
                    try relay.configure(
                        enabled: request.adaptiveEnabled,
                        suffixes: request.resolverDomains,
                        dnsServers: request.publicDNS
                    )
                } catch {
                    try? relay.configure(enabled: false, suffixes: [], dnsServers: [])
                    try? controller.enterFailOpen()
                }
            }
        }
        updateWatchdog()
    }
}

private let arguments = CommandLine.arguments
guard arguments.count == 3 else { exit(64) }
let requestURL = URL(fileURLWithPath: arguments[1])
let responseURL = URL(fileURLWithPath: arguments[2])
let controller = SystemController()
let relay = DNSRelay(controller: controller)
let networkCoordinator = NetworkResilienceCoordinator(controller: controller, relay: relay)
networkCoordinator.start()
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
                    try? controller.enterFailOpen()
                    throw error
                }
            case .repair:
                try controller.repair(request)
            case .restore:
                try relay.configure(enabled: false, suffixes: [], dnsServers: [])
                try controller.restore()
            }
            success = true
            networkCoordinator.requestStateDidChange()
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
