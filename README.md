<p align="center">
  <img src="Assets/Brand/tunnel-detour-icon.png" width="128" alt="TunnelDetour logo">
</p>

# TunnelDetour

TunnelDetour is a local macOS utility that sends selected public services through
your normal network path while a VPN remains connected. You choose the services;
TunnelDetour manages only the matching routes and DNS resolver entries.

> Public Beta for macOS 13 or later. Read the [Vietnamese guide](README.vi.md).

## What it does

- Provides common service groups plus custom domains and IPv4 targets.
- Applies direct routes without connecting, disconnecting, or reconfiguring the VPN.
- Restores routes and resolver files it manages.
- Recovers resolver entries left by an interrupted prior run.
- Runs locally without accounts, telemetry, advertising, or a project backend.

## Before you install

Routing traffic outside a VPN can conflict with workplace, school, or service
policies. Use TunnelDetour only on a Mac and network you are authorized to manage,
and only for destinations you are allowed to route outside the VPN.

The Beta is ad-hoc signed because the project does not yet have an Apple Developer
Program membership. It is not Apple-notarized, so macOS may show a Gatekeeper
warning on first launch.

## Install the Beta

1. Download `TunnelDetour.zip` and `TunnelDetour.zip.sha256` from the latest Beta release.
2. Optionally verify it with `shasum -a 256 -c TunnelDetour.zip.sha256` in Terminal.
3. Unzip the archive and move `TunnelDetour.app` to Applications.
4. Control-click or right-click the app, choose **Open**, then confirm **Open**.

Do not disable Gatekeeper globally.

## Quick start

1. Connect your VPN normally.
2. Open TunnelDetour and select only the service groups you want to use directly.
3. Add custom domains or IPv4 addresses when needed.
   A leading wildcard such as `*.example.com` is stored as `example.com`, which
   already covers its subdomains.
4. Check the normal network interface and public DNS settings. Defaults are `en0`,
   `8.8.8.8`, and `1.1.1.1`; change them if your Mac uses different values.
5. Leave **Private Check (optional)** empty unless you have a private hostname you
   are authorized to use as a health check.
6. Click **Apply** and approve the macOS authorization prompt.
7. Use **Verify** or the site check field to confirm the selected destination is direct.

TunnelDetour may offer a one-time Sponsor invitation only after three successful
Apply operations. It never blocks the app, opens a browser automatically, or sends
usage data. **Maybe Later** waits for ten more successful Apply operations and
**Don't Show Again** disables automatic invitations.

## How it works

TunnelDetour resolves selected destinations with the configured public DNS, adds
narrow host/network routes through the normal gateway, and creates resolver files
only for selected domain suffixes. An installed launch daemon performs the small
set of operations that require administrator privileges. Inputs are validated and
passed as process arguments rather than interpolated into arbitrary commands.

When the normal gateway disappears or changes, the helper temporarily restores
ordinary DNS access, then reapplies the managed routes after the new gateway is
stable. You do not need to Restore Network before changing Wi-Fi.

## Safety and privacy

- Configuration stays under your user Application Support directory.
- Managed helper state stays under the system Application Support directory.
- No analytics, crash uploader, login, cloud sync, or remote configuration exists.
- The optional Google service-range refresh contacts only Google's published range endpoints.
- TunnelDetour does not inspect, proxy, decrypt, or store browsing content.

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Troubleshooting

- **A selected site still uses the VPN:** confirm the service/custom domain is
  selected, click Apply again, then Verify. CDN-backed sites may change addresses.
- **A site stops resolving after a network change:** wait a few seconds for automatic
  recovery. If it remains unavailable, choose **More → Restore Network**, reconnect
  the VPN, then Apply again.
- **The helper does not respond:** choose **More → Remove Helper**, reopen the app,
  and Apply to install a fresh helper.
- **The wrong interface is shown:** use `route -n get default` in Terminal and set
  the interface used by your normal connection.
- **Gatekeeper blocks first launch:** use Finder's Control-click/right-click **Open** flow.

When reporting a bug, remove employer/customer names, private domains, addresses,
VPN names, tokens, and credentials from screenshots or logs.

## Uninstall

1. Open TunnelDetour and choose **More → Restore Network**.
2. Choose **More → Remove Helper** and approve authorization.
3. Quit TunnelDetour and delete the app from Applications.
4. Optionally remove the `TunnelDetour` folder from your user Library's Application
   Support directory using Finder's **Go to Folder**.

## Build from source

Requirements: macOS 13+, Xcode command-line tools, and Swift 5.9 or newer.

```bash
swift test
./package_release.sh dist
```

The release script creates `dist/TunnelDetour.app`, `dist/TunnelDetour.zip`, and a
SHA-256 checksum. Local builds are ad-hoc signed and not notarized.

## Contributing

Issues and focused pull requests are welcome. Please sanitize all network
fixtures before submitting them.

## Sponsor

If TunnelDetour saves you time, you can support continued maintenance through
[GitHub Sponsors](https://github.com/sponsors/mevvmevvcodinggarg). Sponsorship does
not unlock features or guarantee paid support.

## License

[MIT](LICENSE) © 2026 TunnelDetour contributors.
