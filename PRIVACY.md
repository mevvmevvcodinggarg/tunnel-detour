# Privacy

TunnelDetour is a local-only utility. It has no account system, telemetry,
analytics, advertising, cloud synchronization, crash uploader, or
maintainer-operated backend.

Configuration is stored in the TunnelDetour folder under the current user's
Application Support directory. The privileged helper stores only the route and
resolver state required to reverse changes made by the app. Sponsor prompt counts
are stored locally in macOS preferences.

When enabled, Google service-range refresh requests these public documents:

- `https://www.gstatic.com/ipranges/goog.json`
- `https://www.gstatic.com/ipranges/cloud.json`

DNS queries and normal destination traffic still reach the DNS and service
providers selected by the user. TunnelDetour does not inspect, proxy, decrypt, or
store browsing content.
