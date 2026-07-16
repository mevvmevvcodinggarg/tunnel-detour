import Foundation

public enum AdaptiveAction: String, Codable, Equatable {
    case apply
    case repair
    case restore
}

public struct AdaptiveRequest: Codable, Equatable {
    public var id: String
    public var action: AdaptiveAction
    public var wifiInterface: String
    public var publicDNS: [String]
    public var domainTargets: [String]
    public var ipv4Targets: [String]
    public var resolverDomains: [String]
    public var directCIDRs: [String]
    public var adaptiveEnabled: Bool
    public var repairTarget: String?

    public static func apply(config: TunnelDetourConfig, directCIDRs: [String]) -> AdaptiveRequest {
        AdaptiveRequest(
            id: UUID().uuidString,
            action: .apply,
            wifiInterface: config.wifiInterface,
            publicDNS: config.publicDNS,
            domainTargets: config.domainTargets.map(\.value),
            ipv4Targets: config.ipv4Targets.map(\.value),
            resolverDomains: config.resolverDomains,
            directCIDRs: directCIDRs,
            adaptiveEnabled: config.adaptiveDirectSites,
            repairTarget: nil
        )
    }

    public static func restore() -> AdaptiveRequest {
        AdaptiveRequest(
            id: UUID().uuidString,
            action: .restore,
            wifiInterface: "en0",
            publicDNS: [],
            domainTargets: [],
            ipv4Targets: [],
            resolverDomains: [],
            directCIDRs: [],
            adaptiveEnabled: false,
            repairTarget: nil
        )
    }

    public static func repair(input: String, wifiInterface: String, publicDNS: [String]) -> AdaptiveRequest {
        AdaptiveRequest(
            id: UUID().uuidString,
            action: .repair,
            wifiInterface: wifiInterface,
            publicDNS: publicDNS,
            domainTargets: [],
            ipv4Targets: [],
            resolverDomains: [],
            directCIDRs: [],
            adaptiveEnabled: false,
            repairTarget: RouteManager.normalizeHost(input)
        )
    }
}

public struct AdaptiveResponse: Codable, Equatable {
    public var id: String
    public var success: Bool

    public init(id: String, success: Bool) {
        self.id = id
        self.success = success
    }
}

public enum AdaptiveArtifacts {
    public static let label = ProductIdentity.helperLabel
    public static let helperPath = "/Library/PrivilegedHelperTools/\(label)"
    public static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    public static let systemSupportDirectory = "/Library/Application Support/\(ProductIdentity.applicationSupportDirectoryName)"
    public static let statePath = "\(systemSupportDirectory)/adaptive-state.json"

    public static func ipcDirectory(uid: UInt32) -> String {
        "\(systemSupportDirectory)/IPC/\(uid)"
    }

    public static func requestPath(uid: UInt32) -> String {
        "\(ipcDirectory(uid: uid))/adaptive-request.json"
    }

    public static func responsePath(uid: UInt32) -> String {
        "\(ipcDirectory(uid: uid))/adaptive-response.json"
    }

    public static func helperRemovalScript() -> String {
        """
        #!/bin/bash
        set -euo pipefail
        /bin/launchctl bootout system/\(label) >/dev/null 2>&1 || true
        /bin/rm -f '\(plistPath)'
        /bin/rm -f '\(helperPath)'
        /bin/rm -rf '\(systemSupportDirectory)'
        """
    }

    public static func launchDaemonPlist(
        helperPath: String,
        requestPath: String,
        responsePath: String
    ) throws -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [helperPath, requestPath, responsePath],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null"
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
    }
}

public enum AdaptiveBehavior {
    public static let shouldPruneExistingRoutesDuringApply = false
    public static let shouldReplyBeforeDynamicRouting = true
    public static let shouldSuppressIPv6ForDirectDomains = true
    public static let privilegedCommandTimeoutSeconds: TimeInterval = 90

    public static func responseTimeout(for action: AdaptiveAction) -> TimeInterval {
        action == .restore ? 300 : 60
    }

    public static func shouldPreResolveDomains(adaptiveEnabled: Bool) -> Bool {
        !adaptiveEnabled
    }

    public static func shouldInstallBulkCIDRs(googleServicesDirect: Bool, adaptiveEnabled: Bool) -> Bool {
        googleServicesDirect && !adaptiveEnabled
    }

    public static func shouldInstallHelper(
        helperMatches: Bool,
        plistMatches: Bool,
        serviceLoaded: Bool
    ) -> Bool {
        !(helperMatches && plistMatches && serviceLoaded)
    }

    public static func shouldRefreshManagedRoute(alreadyManaged: Bool, force: Bool) -> Bool {
        force || !alreadyManaged
    }

    public static func shouldWriteResolver(existingContents: Data?, desiredContents: String) -> Bool {
        existingContents != Data(desiredContents.utf8)
    }
}

public enum AdaptiveControllerError: LocalizedError {
    case helperMissing
    case operationFailed
    case timedOut

    public var errorDescription: String? { "Operation failed." }
}

public enum AdaptiveController {
    private static var userID: UInt32 { getuid() }
    private static var groupID: UInt32 { getgid() }
    private static var ipcDirectory: URL {
        URL(fileURLWithPath: AdaptiveArtifacts.ipcDirectory(uid: userID), isDirectory: true)
    }
    private static var requestURL: URL { URL(fileURLWithPath: AdaptiveArtifacts.requestPath(uid: userID)) }
    private static var responseURL: URL { URL(fileURLWithPath: AdaptiveArtifacts.responsePath(uid: userID)) }
    private static var bundledHelperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/\(ProductIdentity.helperExecutableName)")
    }

    public static func apply(config: TunnelDetourConfig) throws -> CommandResult {
        let cidrs = AdaptiveBehavior.shouldInstallBulkCIDRs(
            googleServicesDirect: config.googleServicesDirect,
            adaptiveEnabled: config.adaptiveDirectSites
        ) ? GoogleIPRanges.directServiceRoutes() : []
        try ensureInstalled()
        try send(.apply(config: config, directCIDRs: cidrs))
        return CommandResult(exitCode: 0, output: "")
    }

    public static func repair(input: String, wifiInterface: String, publicDNS: [String]) throws -> CommandResult {
        try ensureInstalled()
        try send(.repair(input: input, wifiInterface: wifiInterface, publicDNS: publicDNS))
        return CommandResult(exitCode: 0, output: "")
    }

    public static func restore() throws {
        try ensureInstalled()
        try send(.restore())
    }

    public static func removeHelper() throws {
        try performOrderedRemoval(
            restore: { try AdaptiveController.restore() },
            remove: { _ = try RouteManager.runPrivileged(script: AdaptiveArtifacts.helperRemovalScript()) }
        )
    }

    static func performOrderedRemoval(
        restore: () throws -> Void,
        remove: () throws -> Void
    ) throws {
        try restore()
        try remove()
    }

    private static func ensureInstalled() throws {
        guard FileManager.default.fileExists(atPath: bundledHelperURL.path) else {
            throw AdaptiveControllerError.helperMissing
        }
        let installedURL = URL(fileURLWithPath: AdaptiveArtifacts.helperPath)
        let bundledData = try Data(contentsOf: bundledHelperURL)
        let installedData = try? Data(contentsOf: installedURL)
        let helperMatches = installedData == bundledData
        let plistData = try AdaptiveArtifacts.launchDaemonPlist(
            helperPath: AdaptiveArtifacts.helperPath,
            requestPath: requestURL.path,
            responsePath: responseURL.path
        )
        let installedPlistData = try? Data(contentsOf: URL(fileURLWithPath: AdaptiveArtifacts.plistPath))
        let plistMatches = installedPlistData == plistData
        guard AdaptiveBehavior.shouldInstallHelper(
            helperMatches: helperMatches,
            plistMatches: plistMatches,
            serviceLoaded: isServiceLoaded()
        ) else { return }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnel-detour-helper-\(UUID().uuidString).plist")
        try plistData.write(to: temp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temp) }

        let script = """
        #!/bin/bash
        set -euo pipefail
        /bin/launchctl bootout system/\(AdaptiveArtifacts.label) >/dev/null 2>&1 || true
        /bin/mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons
        /usr/bin/install -d -o root -g wheel -m 711 \(shellQuote(AdaptiveArtifacts.systemSupportDirectory))
        /usr/bin/install -d -o root -g wheel -m 711 \(shellQuote(AdaptiveArtifacts.systemSupportDirectory + "/IPC"))
        /usr/bin/install -d -o \(userID) -g \(groupID) -m 700 \(shellQuote(ipcDirectory.path))
        /usr/bin/install -o root -g wheel -m 755 \(shellQuote(bundledHelperURL.path)) \(shellQuote(AdaptiveArtifacts.helperPath))
        /usr/bin/install -o root -g wheel -m 644 \(shellQuote(temp.path)) \(shellQuote(AdaptiveArtifacts.plistPath))
        /bin/launchctl bootstrap system \(shellQuote(AdaptiveArtifacts.plistPath))
        /bin/launchctl kickstart -k system/\(AdaptiveArtifacts.label)
        """
        _ = try RouteManager.runPrivileged(script: script)
    }

    private static func isServiceLoaded(label: String = AdaptiveArtifacts.label) -> Bool {
        (try? RouteManager.run(
            "/bin/launchctl",
            arguments: ["print", "system/\(label)"]
        )) != nil
    }

    private static func send(_ request: AdaptiveRequest) throws {
        try send(request, requestURL: requestURL, responseURL: responseURL)
    }

    private static func send(
        _ request: AdaptiveRequest,
        requestURL: URL,
        responseURL: URL
    ) throws {
        let directory = requestURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)

        let deadline = Date().addingTimeInterval(AdaptiveBehavior.responseTimeout(for: request.action))
        while Date() < deadline {
            if let data = try? Data(contentsOf: responseURL),
               let response = try? JSONDecoder().decode(AdaptiveResponse.self, from: data),
               response.id == request.id {
                guard response.success else { throw AdaptiveControllerError.operationFailed }
                return
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        throw AdaptiveControllerError.timedOut
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
