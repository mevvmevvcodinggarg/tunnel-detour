import Foundation

public struct CommandResult: Equatable {
    public var exitCode: Int32
    public var output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public enum RouteManagerError: LocalizedError {
    case commandFailed(String)
    case commandTimedOut
    case invalidTarget
    case missingGateway(String)
    case missingPublicDNS

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return output
        case .commandTimedOut:
            return "The operation took too long."
        case .invalidTarget:
            return "Enter a valid URL, hostname, or IPv4 address."
        case .missingGateway(let interface):
            return "Cannot find Wi-Fi gateway for \(interface)."
        case .missingPublicDNS:
            return "At least one public DNS address is required."
        }
    }
}

public struct RouteManager {
    public static func normalizeHost(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }

        let hostFromURL: String?
        if trimmed.contains("://"), let url = URL(string: trimmed) {
            hostFromURL = url.host
        } else {
            hostFromURL = nil
        }

        var host = hostFromURL ?? trimmed
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        return host.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    public static func inferResolverDomain(from input: String) -> String? {
        let host = normalizeHost(input)
        guard !host.isEmpty, !isIPv4(host) else { return nil }

        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts.suffix(2).joined(separator: ".")
    }

    public static func isIPv4(_ input: String) -> Bool {
        let parts = input.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = UInt8(part) else { return false }
            return String(value) == part || part == "0"
        }
    }

    public static func classifyRouteInterfaces(
        _ interfaces: [String],
        directInterface: String
    ) -> SiteRouteState {
        guard !interfaces.isEmpty else { return .unavailable }

        let directCount = interfaces.filter { $0 == directInterface }.count
        if directCount == interfaces.count {
            return .direct
        }
        if directCount == 0 {
            return .privatePath
        }
        return .mixed
    }

    public static func isConfiguredSite(_ input: String, config: TunnelDetourConfig) -> Bool {
        let host = normalizeHost(input)
        return config.domainTargets.contains {
            normalizeHost($0.value) == host
        }
    }

    public static func directTarget(for input: String) -> RouteTarget? {
        let value = normalizeHost(input)
        guard !value.isEmpty else { return nil }
        return RouteTarget(
            kind: isIPv4(value) ? .ipv4 : .domain,
            value: value
        )
    }

    public static func siteRouteState(
        for input: String,
        directInterface: String
    ) throws -> SiteRouteState {
        let host = normalizeHost(input)
        guard !host.isEmpty else { return .unavailable }

        if isIPv4(host) {
            guard let route = try? run("/sbin/route", arguments: ["-n", "get", host]),
                  let interface = parseRouteInterface(route.output) else {
                return .unavailable
            }
            return classifyRouteInterfaces([interface], directInterface: directInterface)
        }

        let lookup = try run(
            "/usr/bin/dscacheutil",
            arguments: ["-q", "host", "-a", "name", host]
        )
        let addresses = parseResolvedAddresses(lookup.output)
        var interfaces: [String] = []

        for address in addresses {
            let arguments = address.isIPv6
                ? ["-n", "get", "-inet6", address.value]
                : ["-n", "get", address.value]
            guard let route = try? run("/sbin/route", arguments: arguments),
                  let interface = parseRouteInterface(route.output) else {
                continue
            }
            interfaces.append(interface)
        }

        return classifyRouteInterfaces(interfaces, directInterface: directInterface)
    }

    public static func makeRepairScript(
        input: String,
        wifiGateway: String,
        publicDNS: [String]
    ) throws -> String {
        let host = normalizeHost(input)
        guard !host.isEmpty, isIPv4(host) || isValidHostname(host) else {
            throw RouteManagerError.invalidTarget
        }

        let dnsServers = unique(publicDNS.map(normalizeHost).filter(isIPv4))
        if !isIPv4(host), dnsServers.isEmpty {
            throw RouteManagerError.missingPublicDNS
        }

        var lines = [
            "#!/bin/bash",
            "set -euo pipefail",
            "",
            "GW=\(shellDoubleQuoted(wifiGateway))"
        ]

        for dns in dnsServers {
            lines.append("/sbin/route -n delete -host \(shellDoubleQuoted(dns)) >/dev/null 2>&1 || true")
            lines.append("/sbin/route -n add -host \(shellDoubleQuoted(dns)) \"$GW\" >/dev/null")
        }

        if isIPv4(host) {
            lines.append("/sbin/route -n delete -host \(shellDoubleQuoted(host)) >/dev/null 2>&1 || true")
            lines.append("/sbin/route -n add -host \(shellDoubleQuoted(host)) \"$GW\" >/dev/null")
        } else {
            lines += [
                "IPS=\"$(",
                "  {",
                "    for dns in \(dnsServers.map(shellDoubleQuoted).joined(separator: " ")); do",
                "      /usr/bin/dig @\"$dns\" +time=1 +tries=1 +short A \(shellDoubleQuoted(host)) 2>/dev/null || true",
                "    done",
                "  } | /usr/bin/grep -E '^[0-9.]+$' | /usr/bin/sort -u || true",
                ")\"",
                "[[ -n \"$IPS\" ]] || exit 3",
                "while IFS= read -r ip; do",
                "  [[ -z \"$ip\" ]] && continue",
                "  /sbin/route -n delete -host \"$ip\" >/dev/null 2>&1 || true",
                "  /sbin/route -n add -host \"$ip\" \"$GW\" >/dev/null",
                "done <<< \"$IPS\""
            ]
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func repair(
        input: String,
        wifiInterface: String,
        publicDNS: [String]
    ) throws -> CommandResult {
        try AdaptiveController.repair(
            input: input,
            wifiInterface: wifiInterface,
            publicDNS: publicDNS
        )
    }

    public static func makeApplyScript(
        config: TunnelDetourConfig,
        wifiGateway: String,
        directCIDRs: [String] = []
    ) -> String {
        let publicDNS = unique(config.publicDNS.map(normalizeHost).filter(isIPv4))
        let domains = unique(config.domainTargets.map { normalizeHost($0.value) }.filter { !$0.isEmpty && !isIPv4($0) })
        let ipv4Targets = unique(config.ipv4Targets.map { normalizeHost($0.value) }.filter(isIPv4))
        let networkTargets = unique(directCIDRs)
        let inferredResolverDomains = domains.compactMap { inferResolverDomain(from: $0) }
        let resolverDomains = unique((config.resolverDomains + inferredResolverDomains).map(normalizeHost).filter { !$0.isEmpty && !isIPv4($0) })
        let gateway = shellDoubleQuoted(wifiGateway)

        var lines: [String] = [
            "#!/bin/bash",
            "set -euo pipefail",
            "",
            "GW=\(gateway)",
            "echo \"Wi-Fi interface: \(shellEcho(config.wifiInterface))\"",
            "echo \"Wi-Fi gateway:   $GW\"",
            "echo",
            "echo \"Routing public DNS directly via $GW...\""
        ]

        for dns in publicDNS {
            lines.append("/sbin/route -n delete -host \(shellDoubleQuoted(dns)) >/dev/null 2>&1 || true")
            lines.append("/sbin/route -n add -host \(shellDoubleQuoted(dns)) \(gateway) >/dev/null")
            lines.append("echo \"  \(shellEcho(dns))\"")
            lines.append("/sbin/route -n get \(shellDoubleQuoted(dns)) | /usr/bin/egrep 'gateway|interface' || true")
        }

        if !networkTargets.isEmpty {
            lines += [
                "",
                "echo",
                "echo \"Routing Google services directly via $GW...\""
            ]
        }
        for cidr in networkTargets {
            lines.append("/sbin/route -n delete -net \(shellDoubleQuoted(cidr)) >/dev/null 2>&1 || true")
            lines.append("/sbin/route -n add -net \(shellDoubleQuoted(cidr)) \(gateway) >/dev/null")
            lines.append("echo \"  \(shellEcho(cidr))\"")
        }

        lines += [
            "",
            "echo",
            "echo \"Installing per-domain public DNS resolvers...\"",
            "/bin/mkdir -p /etc/resolver"
        ]

        for resolverDomain in resolverDomains {
            lines.append("{")
            for dns in publicDNS {
                lines.append("  echo \(shellDoubleQuoted("nameserver \(dns)"))")
            }
            lines.append("} > \(shellDoubleQuoted("/etc/resolver/\(resolverDomain)"))")
            lines.append("echo \"  /etc/resolver/\(shellEcho(resolverDomain)) -> \(publicDNS.map(shellEcho).joined(separator: " "))\"")
        }

        lines += [
            "",
            "/usr/bin/dscacheutil -flushcache",
            "/usr/bin/killall -HUP mDNSResponder 2>/dev/null || true",
            "",
            "echo",
            "echo \"Routing selected domains directly via $GW...\"",
            "DOMAIN_FILE=\"$(/usr/bin/mktemp -t tunnel-detour-domains)\"",
            "RESULT_FILE=\"$(/usr/bin/mktemp -t tunnel-detour-results)\"",
            "cleanup() { /bin/rm -f \"$DOMAIN_FILE\" \"$RESULT_FILE\"; }",
            "trap cleanup EXIT"
        ]

        if domains.isEmpty {
            lines.append(": > \"$DOMAIN_FILE\"")
        } else {
            lines.append("/usr/bin/printf '%s\\n' \(domains.map(shellDoubleQuoted).joined(separator: " ")) > \"$DOMAIN_FILE\"")
        }

        lines += [
            "if [[ -s \"$DOMAIN_FILE\" ]]; then",
            "  /usr/bin/xargs -P 12 -n 1 /bin/bash -c '",
            "  host=\"$1\"",
            "  for dns in \(publicDNS.map(shellDoubleQuoted).joined(separator: " ")); do",
            "    /usr/bin/dig @\"$dns\" +time=1 +tries=1 +short A \"$host\" 2>/dev/null || true",
            "  done",
            "  ' _ < \"$DOMAIN_FILE\" | /usr/bin/grep -E '^[0-9.]+$' | /usr/bin/sort -u > \"$RESULT_FILE\" || true",
            "else",
            "  : > \"$RESULT_FILE\"",
            "fi",
            "if [[ ! -s \"$RESULT_FILE\" ]]; then",
            "  echo \"  No IPv4 records found\"",
            "else",
            "  while IFS= read -r ip; do",
            "    [[ -z \"$ip\" ]] && continue",
            "    /sbin/route -n delete -host \"$ip\" >/dev/null 2>&1 || true",
            "    /sbin/route -n add -host \"$ip\" \"$GW\" >/dev/null",
            "  done < \"$RESULT_FILE\"",
            "fi"
        ]

        if !ipv4Targets.isEmpty {
            lines += [
                "",
                "echo",
                "echo \"Routing fixed IPv4 targets directly via $GW...\""
            ]
        }
        for ip in ipv4Targets {
            lines.append("/sbin/route -n delete -host \(shellDoubleQuoted(ip)) >/dev/null 2>&1 || true")
            lines.append("/sbin/route -n add -host \(shellDoubleQuoted(ip)) \(gateway) >/dev/null")
            lines.append("echo \"  \(shellEcho(ip))\"")
            lines.append("/sbin/route -n get \(shellDoubleQuoted(ip)) | /usr/bin/egrep 'gateway|interface' || true")
        }

        if !config.privateCheckHost.isEmpty {
            let checkHost = normalizeHost(config.privateCheckHost)
            lines += [
                "",
                "echo",
                "echo \"Verify private host still uses the expected route:\"",
                "/usr/bin/dscacheutil -q host -a name \(shellDoubleQuoted(checkHost)) | /usr/bin/awk '/ip_address:/ {print $2}' | /usr/bin/sort -u | while IFS= read -r ip; do",
                "  [[ -z \"$ip\" ]] && continue",
                "  echo \"  \(shellEcho(checkHost)) -> $ip\"",
                "  /sbin/route -n get \"$ip\" | /usr/bin/egrep 'gateway|interface' || true",
                "done"
            ]
        }

        lines += [
            "",
            "echo",
            "echo \"Done. Only selected public targets use direct Wi-Fi routes.\"",
            ""
        ]

        return lines.joined(separator: "\n")
    }

    public static func makeVerifyScript(config: TunnelDetourConfig) -> String {
        let publicDNS = unique(config.publicDNS.map(normalizeHost).filter(isIPv4))
        let domains = unique(config.domainTargets.map { normalizeHost($0.value) }.filter { !$0.isEmpty && !isIPv4($0) })
        let ipv4Targets = unique(config.ipv4Targets.map { normalizeHost($0.value) }.filter(isIPv4))
        let privateCheckHost = normalizeHost(config.privateCheckHost)

        var lines: [String] = [
            "#!/bin/bash",
            "set -uo pipefail",
            "echo \"== Public DNS routes ==\""
        ]

        for dns in publicDNS {
            lines.append("echo \(shellDoubleQuoted(dns))")
            lines.append("/sbin/route -n get \(shellDoubleQuoted(dns)) | /usr/bin/egrep 'gateway|interface' || true")
        }

        lines += ["", "echo", "echo \"== Direct site routes ==\""]
        for domain in domains {
            lines += [
                "echo",
                "echo \(shellDoubleQuoted(domain))",
                "ips=\"$(/usr/bin/dscacheutil -q host -a name \(shellDoubleQuoted(domain)) | /usr/bin/awk '/ip_address:/ {print $2}' | /usr/bin/sort -u)\"",
                "if [[ -z \"$ips\" ]]; then",
                "  for dns in \(publicDNS.map(shellDoubleQuoted).joined(separator: " ")); do",
                "    /usr/bin/dig @\"$dns\" +time=2 +tries=1 +short A \(shellDoubleQuoted(domain)) 2>/dev/null || true",
                "  done | /usr/bin/grep -E '^[0-9.]+$' | /usr/bin/sort -u | while IFS= read -r ip; do /sbin/route -n get \"$ip\" | /usr/bin/egrep 'gateway|interface' || true; done",
                "else",
                "  while IFS= read -r ip; do /sbin/route -n get \"$ip\" | /usr/bin/egrep 'gateway|interface' || true; done <<< \"$ips\"",
                "fi"
            ]
        }

        if !ipv4Targets.isEmpty {
            lines += ["", "echo", "echo \"== Fixed IPv4 routes ==\""]
        }
        for ip in ipv4Targets {
            lines.append("echo \(shellDoubleQuoted(ip))")
            lines.append("/sbin/route -n get \(shellDoubleQuoted(ip)) | /usr/bin/egrep 'gateway|interface' || true")
        }

        if !privateCheckHost.isEmpty {
            lines += [
                "",
                "echo",
                "echo \"== Private route check ==\"",
                "echo \(shellDoubleQuoted(privateCheckHost))",
                "/usr/bin/dscacheutil -q host -a name \(shellDoubleQuoted(privateCheckHost)) | /usr/bin/awk '/ip_address:/ {print $2}' | /usr/bin/sort -u | while IFS= read -r ip; do",
                "  echo \"$ip\"",
                "  /sbin/route -n get \"$ip\" | /usr/bin/egrep 'gateway|interface' || true",
                "done"
            ]
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func wifiGateway(interface: String) throws -> String {
        let result = try run(
            "/usr/sbin/ipconfig",
            arguments: ["getoption", interface, "router"]
        )
        let gateway = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !gateway.isEmpty else {
            throw RouteManagerError.missingGateway(interface)
        }
        return gateway
    }

    public static func apply(config: TunnelDetourConfig) throws -> CommandResult {
        try AdaptiveController.apply(config: config)
    }

    public static func verify(config: TunnelDetourConfig) throws -> CommandResult {
        let result = try runShell(script: makeVerifyScript(config: config))
        return CommandResult(exitCode: result.exitCode, output: "")
    }

    public static func runShell(script: String) throws -> CommandResult {
        try run("/bin/bash", arguments: ["-lc", script])
    }

    public static func runPrivileged(script: String) throws -> CommandResult {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunnel-detour-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let appleScript = "do shell script \"/bin/bash \" & quoted form of \(appleScriptQuoted(scriptURL.path)) with administrator privileges"
        return try run(
            "/usr/bin/osascript",
            arguments: ["-e", appleScript],
            timeout: AdaptiveBehavior.privilegedCommandTimeoutSeconds
        )
    }

    public static func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                throw RouteManagerError.commandTimedOut
            }
        }
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        let combined = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")

        let result = CommandResult(exitCode: process.terminationStatus, output: combined)
        guard result.exitCode == 0 else {
            throw RouteManagerError.commandFailed(combined)
        }
        return result
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }

    private static func parseResolvedAddresses(_ output: String) -> [(value: String, isIPv6: Bool)] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("ip_address:") {
                return (value.replacingOccurrences(of: "ip_address:", with: "")
                    .trimmingCharacters(in: .whitespaces), false)
            }
            if value.hasPrefix("ipv6_address:") {
                return (value.replacingOccurrences(of: "ipv6_address:", with: "")
                    .trimmingCharacters(in: .whitespaces), true)
            }
            return nil
        }
    }

    private static func parseRouteInterface(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("interface:") {
                return value.replacingOccurrences(of: "interface:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func isValidHostname(_ value: String) -> Bool {
        guard value.utf8.count <= 253 else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.utf8.count <= 63,
                  label.first != "-",
                  label.last != "-" else {
                return false
            }
            return label.allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber || character == "-")
            }
        }
    }

    private static func shellDoubleQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        return "\"\(escaped)\""
    }

    private static func shellEcho(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    private static func appleScriptQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
