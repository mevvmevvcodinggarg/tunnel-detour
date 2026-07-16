import Foundation

public enum RouteTargetKind: String, Codable, Equatable, Hashable, CaseIterable {
    case domain
    case ipv4
}

public struct RouteTarget: Codable, Equatable, Hashable {
    public var kind: RouteTargetKind
    public var value: String

    public init(kind: RouteTargetKind, value: String) {
        self.kind = kind
        self.value = value
    }
}

public struct ServiceDirectGroup: Equatable, Hashable {
    public let id: String
    public let category: String
    public let name: String
    public let domains: [String]

    public init(id: String, category: String, name: String, domains: [String]) {
        self.id = id
        self.category = category
        self.name = name
        self.domains = domains
    }
}

public struct TunnelDetourConfig: Codable, Equatable {
    public var schemaVersion: Int
    public var wifiInterface: String
    public var publicDNS: [String]
    public var customDomainTargets: [RouteTarget]
    public var enabledServiceIDs: Set<String>
    public var domainTargets: [RouteTarget] {
        Self.effectiveDomainTargets(
            customDomainTargets: customDomainTargets,
            enabledServiceIDs: enabledServiceIDs
        )
    }
    public var ipv4Targets: [RouteTarget]
    public var resolverDomains: [String]
    public var privateCheckHost: String
    public var googleServicesDirect: Bool
    public var adaptiveDirectSites: Bool

    public init(
        wifiInterface: String,
        publicDNS: [String],
        customDomainTargets: [RouteTarget],
        enabledServiceIDs: Set<String>,
        ipv4Targets: [RouteTarget],
        privateCheckHost: String,
        googleServicesDirect: Bool = true,
        adaptiveDirectSites: Bool = true,
        schemaVersion: Int = TunnelDetourConfig.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.wifiInterface = wifiInterface
        self.publicDNS = publicDNS
        self.customDomainTargets = customDomainTargets
        self.enabledServiceIDs = enabledServiceIDs
        self.ipv4Targets = ipv4Targets
        self.resolverDomains = Self.resolverDomains(for: Self.effectiveDomainTargets(
            customDomainTargets: customDomainTargets,
            enabledServiceIDs: enabledServiceIDs
        ).map(\.value))
        self.privateCheckHost = privateCheckHost
        self.googleServicesDirect = googleServicesDirect
        self.adaptiveDirectSites = adaptiveDirectSites
    }

    public init(
        wifiInterface: String,
        publicDNS: [String],
        domainTargets: [RouteTarget],
        ipv4Targets: [RouteTarget],
        resolverDomains: [String],
        privateCheckHost: String,
        googleServicesDirect: Bool = true,
        adaptiveDirectSites: Bool = true,
        schemaVersion: Int = TunnelDetourConfig.currentSchemaVersion
    ) {
        self.init(
            wifiInterface: wifiInterface,
            publicDNS: publicDNS,
            customDomainTargets: domainTargets,
            enabledServiceIDs: Self.defaultEnabledServiceIDs,
            ipv4Targets: ipv4Targets,
            privateCheckHost: privateCheckHost,
            googleServicesDirect: googleServicesDirect,
            adaptiveDirectSites: adaptiveDirectSites,
            schemaVersion: schemaVersion
        )
        self.resolverDomains = resolverDomains
    }

    public static let currentSchemaVersion = 8

    public static let previousDefaultDomainValues: [String] = [
        // AI assistants and model APIs
        "api.openai.com",
        "chatgpt.com",
        "api.anthropic.com",
        "claude.ai",
        "gemini.google.com",
        "aistudio.google.com",
        "ai.google.dev",
        "openrouter.ai",
        "api.openrouter.ai",
        "perplexity.ai",
        "www.perplexity.ai",

        // Search and Google surfaces
        "google.com",
        "www.google.com",
        "ogs.google.com",
        "clients1.google.com",
        "clients2.google.com",
        "www.gstatic.com",
        "ssl.gstatic.com",
        "fonts.googleapis.com",
        "fonts.gstatic.com",
        "bing.com",
        "www.bing.com",
        "duckduckgo.com",
        "yahoo.com",
        "search.yahoo.com",

        // Google productivity
        "mail.google.com",
        "drive.google.com",
        "docs.google.com",
        "sheets.google.com",
        "slides.google.com",

        // Video, music, and entertainment
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "youtu.be",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com",
        "youtubei.googleapis.com",
        "googlevideo.com",
        "ytimg.com",
        "i.ytimg.com",
        "s.ytimg.com",
        "yt3.ggpht.com",
        "netflix.com",
        "www.netflix.com",
        "fast.com",
        "twitch.tv",
        "www.twitch.tv",
        "static-cdn.jtvnw.net",
        "spotify.com",
        "open.spotify.com",
        "scdn.co",
        "soundcloud.com",
        "www.soundcloud.com",
        "imdb.com",
        "www.imdb.com",

        // Social and chat
        "reddit.com",
        "www.reddit.com",
        "old.reddit.com",
        "redditstatic.com",
        "redd.it",
        "x.com",
        "twitter.com",
        "abs.twimg.com",
        "pbs.twimg.com",
        "video.twimg.com",
        "t.co",
        "facebook.com",
        "www.facebook.com",
        "static.xx.fbcdn.net",
        "instagram.com",
        "www.instagram.com",
        "cdninstagram.com",
        "threads.net",
        "www.threads.net",
        "tiktok.com",
        "www.tiktok.com",
        "whatsapp.com",
        "web.whatsapp.com",
        "static.whatsapp.net",
        "discord.com",
        "cdn.discordapp.com",
        "media.discordapp.net",
        "telegram.org",
        "web.telegram.org",
        "t.me",
        "linkedin.com",
        "www.linkedin.com",
        "static.licdn.com",
        "slack.com",
        "app.slack.com",
        "slack-edge.com",
        "slack-imgs.com",
        "slack-files.com",

        // Developer tools and package registries
        "github.com",
        "api.github.com",
        "gist.github.com",
        "raw.githubusercontent.com",
        "objects.githubusercontent.com",
        "github.githubassets.com",
        "avatars.githubusercontent.com",
        "codeload.github.com",
        "ghcr.io",
        "pkg-containers.githubusercontent.com",
        "gitlab.com",
        "bitbucket.org",
        "stackoverflow.com",
        "stackexchange.com",
        "superuser.com",
        "serverfault.com",
        "npmjs.com",
        "www.npmjs.com",
        "registry.npmjs.org",
        "pypi.org",
        "files.pythonhosted.org",
        "repo.maven.apache.org",
        "plugins.gradle.org",
        "rubygems.org",
        "crates.io",
        "static.crates.io",
        "go.dev",
        "golang.org",
        "proxy.golang.org",
        "sum.golang.org",
        "pkg.go.dev",
        "docker.io",
        "hub.docker.com",
        "registry-1.docker.io",
        "auth.docker.io",
        "production.cloudflare.docker.com",

        // CDN and public web assets
        "cloudflare.com",
        "cdnjs.cloudflare.com",
        "jsdelivr.net",
        "cdn.jsdelivr.net",
        "unpkg.com",
        "esm.sh",
        "skypack.dev",

        // Docs, learning, and news
        "wikipedia.org",
        "en.wikipedia.org",
        "wikimedia.org",
        "developer.mozilla.org",
        "mdn.github.io",
        "docs.python.org",
        "nodejs.org",
        "react.dev",
        "nextjs.org",
        "vite.dev",
        "tailwindcss.com",
        "kubernetes.io",
        "helm.sh",
        "terraform.io",
        "developer.hashicorp.com",
        "docs.aws.amazon.com",
        "cloud.google.com",
        "learn.microsoft.com",
        "medium.com",
        "dev.to",
        "news.ycombinator.com",
        "producthunt.com",
        "nytimes.com",
        "www.nytimes.com",
        "bbc.com",
        "www.bbc.com",
        "cnn.com",
        "www.cnn.com",

        // Public productivity and file tools
        "dropbox.com",
        "www.dropbox.com",
        "dropboxusercontent.com",
        "notion.so",
        "www.notion.so",
        "miro.com",
        "www.miro.com",
        "canva.com",
        "www.canva.com"
    ]

    private static let explicitServiceGroups: [ServiceDirectGroup] = [
        ServiceDirectGroup(id: "slack", category: "Collaboration", name: "Slack", domains: ["slack.com", "slack-edge.com", "slack-imgs.com", "slack-files.com"]),
        ServiceDirectGroup(id: "clickup", category: "Collaboration", name: "ClickUp", domains: ["clickup.com", "clickup-au.com", "clickup-attachments.com", "codox.io"]),
        ServiceDirectGroup(id: "linear", category: "Collaboration", name: "Linear", domains: ["linear.app"]),
        ServiceDirectGroup(id: "atlassian", category: "Collaboration", name: "Jira & Confluence", domains: ["atl-paas.net", "atlassian.com", "ss-inf.net", "atlassian.net", "jira.com", "atlassian-dev.net", "atlassian-3p.com", "teamworkgraph.com", "teamworkgraph.ai"]),
        ServiceDirectGroup(id: "trello", category: "Collaboration", name: "Trello", domains: ["trello.com", "trellocdn.com"]),
        ServiceDirectGroup(id: "figma", category: "Collaboration", name: "Figma", domains: ["figma.com", "figma.site", "figma.app"]),
        ServiceDirectGroup(id: "notion", category: "Collaboration", name: "Notion", domains: ["notion.so"]),
        ServiceDirectGroup(id: "miro", category: "Collaboration", name: "Miro", domains: ["miro.com"]),
        ServiceDirectGroup(id: "dropbox", category: "Collaboration", name: "Dropbox", domains: ["dropbox.com", "dropboxusercontent.com"]),
        ServiceDirectGroup(id: "canva", category: "Collaboration", name: "Canva", domains: ["canva.com"]),

        ServiceDirectGroup(id: "github", category: "Developer", name: "GitHub", domains: ["github.com", "githubusercontent.com", "githubassets.com", "ghcr.io"]),
        ServiceDirectGroup(id: "gitlab", category: "Developer", name: "GitLab", domains: ["gitlab.com"]),
        ServiceDirectGroup(id: "bitbucket", category: "Developer", name: "Bitbucket", domains: ["bitbucket.org"]),
        ServiceDirectGroup(id: "postman", category: "Developer", name: "Postman", domains: ["postman.com", "postman.co", "getpostman.com", "pstmn.io"]),
        ServiceDirectGroup(id: "npm", category: "Developer", name: "npm", domains: ["npmjs.com", "npmjs.org"]),
        ServiceDirectGroup(id: "python", category: "Developer", name: "Python Package Index", domains: ["pypi.org", "pythonhosted.org"]),
        ServiceDirectGroup(id: "java", category: "Developer", name: "Maven & Gradle", domains: ["maven.apache.org", "gradle.org"]),
        ServiceDirectGroup(id: "go", category: "Developer", name: "Go", domains: ["go.dev", "golang.org"]),
        ServiceDirectGroup(id: "docker", category: "Developer", name: "Docker", domains: ["docker.io"]),

        ServiceDirectGroup(id: "vercel", category: "Deploy & Cloud", name: "Vercel", domains: ["vercel.com", "vercel.app", "vercel-insights.com"]),
        ServiceDirectGroup(id: "netlify", category: "Deploy & Cloud", name: "Netlify", domains: ["netlify.com", "netlify.app", "netlifyusercontent.com"]),
        ServiceDirectGroup(id: "cloudflare", category: "Deploy & Cloud", name: "Cloudflare", domains: ["cloudflare.com", "cloudflare-dns.com"]),
        ServiceDirectGroup(id: "render", category: "Deploy & Cloud", name: "Render", domains: ["render.com", "onrender.com"]),
        ServiceDirectGroup(id: "railway", category: "Deploy & Cloud", name: "Railway", domains: ["railway.app", "railway.com"]),
        ServiceDirectGroup(id: "fly", category: "Deploy & Cloud", name: "Fly.io", domains: ["fly.io", "fly.dev"]),
        ServiceDirectGroup(id: "digitalocean", category: "Deploy & Cloud", name: "DigitalOcean", domains: ["digitalocean.com", "digitaloceanspaces.com"]),

        ServiceDirectGroup(id: "sentry", category: "Observability", name: "Sentry", domains: ["sentry.io", "sentry-cdn.com"]),
        ServiceDirectGroup(id: "datadog", category: "Observability", name: "Datadog", domains: ["datadoghq.com", "datadoghq.eu"]),
        ServiceDirectGroup(id: "grafana", category: "Observability", name: "Grafana Cloud", domains: ["grafana.com", "grafana.net"])
    ]

    public static let serviceGroups: [ServiceDirectGroup] = {
        let explicitDomains = Set(explicitServiceGroups.flatMap(\.domains))
        let everydayDomains = previousDefaultDomainValues.filter { domain in
            !explicitDomains.contains { root in
                domain == root || domain.hasSuffix(".\(root)")
            }
        }
        let everyday = ServiceDirectGroup(
            id: "everyday-web",
            category: "General",
            name: "Everyday Web & Media",
            domains: everydayDomains
        )
        return [everyday] + explicitServiceGroups
    }()

    public static let defaultEnabledServiceIDs = Set(serviceGroups.map(\.id))

    public static let defaults = TunnelDetourConfig(
        wifiInterface: "en0",
        publicDNS: ["8.8.8.8", "1.1.1.1"],
        customDomainTargets: [],
        enabledServiceIDs: defaultEnabledServiceIDs,
        ipv4Targets: [],
        privateCheckHost: ""
    )

    public static func migratedToCurrentDefaults(_ config: TunnelDetourConfig) -> TunnelDetourConfig {
        guard config.schemaVersion < currentSchemaVersion else { return config }

        let previousDefaultTargets = Set(previousDefaultDomainValues)
        let customDomainTargets = config.customDomainTargets.filter {
            $0.kind != .domain || !previousDefaultTargets.contains($0.value)
        }
        return TunnelDetourConfig(
            wifiInterface: config.wifiInterface,
            publicDNS: merge(config.publicDNS, defaults.publicDNS),
            customDomainTargets: customDomainTargets,
            enabledServiceIDs: defaultEnabledServiceIDs,
            ipv4Targets: config.ipv4Targets,
            privateCheckHost: config.privateCheckHost,
            googleServicesDirect: config.googleServicesDirect,
            adaptiveDirectSites: config.adaptiveDirectSites,
            schemaVersion: currentSchemaVersion
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case wifiInterface
        case publicDNS
        case domainTargets
        case customDomainTargets
        case enabledServiceIDs
        case ipv4Targets
        case resolverDomains
        case privateCheckHost
        case googleServicesDirect
        case adaptiveDirectSites
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        wifiInterface = try container.decode(String.self, forKey: .wifiInterface)
        publicDNS = try container.decode([String].self, forKey: .publicDNS)
        let previousDomainTargets = try container.decodeIfPresent([RouteTarget].self, forKey: .domainTargets) ?? []
        customDomainTargets = try container.decodeIfPresent([RouteTarget].self, forKey: .customDomainTargets) ?? previousDomainTargets
        enabledServiceIDs = try container.decodeIfPresent(Set<String>.self, forKey: .enabledServiceIDs) ?? Self.defaultEnabledServiceIDs
        ipv4Targets = try container.decode([RouteTarget].self, forKey: .ipv4Targets)
        resolverDomains = Self.resolverDomains(for: Self.effectiveDomainTargets(
            customDomainTargets: customDomainTargets,
            enabledServiceIDs: enabledServiceIDs
        ).map(\.value))
        privateCheckHost = try container.decodeIfPresent(String.self, forKey: .privateCheckHost) ?? ""
        googleServicesDirect = try container.decodeIfPresent(Bool.self, forKey: .googleServicesDirect) ?? true
        adaptiveDirectSites = try container.decodeIfPresent(Bool.self, forKey: .adaptiveDirectSites) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(wifiInterface, forKey: .wifiInterface)
        try container.encode(publicDNS, forKey: .publicDNS)
        try container.encode(customDomainTargets, forKey: .customDomainTargets)
        try container.encode(enabledServiceIDs, forKey: .enabledServiceIDs)
        try container.encode(ipv4Targets, forKey: .ipv4Targets)
        try container.encode(resolverDomains, forKey: .resolverDomains)
        try container.encode(privateCheckHost, forKey: .privateCheckHost)
        try container.encode(googleServicesDirect, forKey: .googleServicesDirect)
        try container.encode(adaptiveDirectSites, forKey: .adaptiveDirectSites)
    }

    private static func effectiveDomainTargets(
        customDomainTargets: [RouteTarget],
        enabledServiceIDs: Set<String>
    ) -> [RouteTarget] {
        let serviceTargets = serviceGroups
            .filter { enabledServiceIDs.contains($0.id) }
            .flatMap(\.domains)
            .map { RouteTarget(kind: .domain, value: $0) }
        return merge(customDomainTargets, serviceTargets)
    }

    private static func resolverDomains(for hosts: [String]) -> [String] {
        merge(hosts.compactMap { host in
            let parts = host.split(separator: ".").map(String.init)
            guard parts.count >= 2 else { return nil }
            return parts.suffix(2).joined(separator: ".")
        }, [])
    }

    private static func merge<T: Hashable>(_ primary: [T], _ secondary: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        for value in primary + secondary {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}

public enum AppStatus: String, Equatable {
    case ready = "Ready"
    case needsApply = "Needs Apply"
    case applying = "Applying"
    case verified = "Verified"
    case error = "Error"
}

public struct RouteCheck: Equatable {
    public var target: String
    public var gateway: String
    public var interface: String

    public init(target: String, gateway: String, interface: String) {
        self.target = target
        self.gateway = gateway
        self.interface = interface
    }
}
