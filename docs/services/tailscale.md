# Service: Tailscale

## What it does

All remote access to the lab, with no ports open on the router. It also carries tailnet-wide DNS through the Pi-holes, and provides HTTPS for internal services.

## Configuration

| Setting | Choice |
|---|---|
| DNS | Global nameservers = both Pi-holes, with "Override local DNS" on |
| Exit node | The [NUC](../hosts/nuc-docker-host.md) |
| Subnet route | Home LAN, advertised by **both** the primary DNS Pi and the NUC, for redundancy |
| Key expiry | Disabled on the three infrastructure nodes only |
| HTTPS | `tailscale serve` on the NUC for Vaultwarden and ntfy; Funnel never used |
| Family phone | On the tailnet, but with no subnet routes, so router and DNS admin pages stay out of reach |

## Decisions

- **Two subnet routers:** One advertiser meant losing LAN access whenever the primary Pi went down.
- **Load-bearing nodes:** `tailscaled` on both Pis provides tailnet DNS. Disabling it on one node caused the [tailnet DNS outage](../incidents/2026-07-27-tailnet-dns-outage.md).
- **Advertising routes replaces the list:** `--advertise-routes=` replaces the advertised set; it doesn't add to it. Exit-node advertising is a separate flag.

## Diagnostics I rely on

- **`tailscale dns status`:** Shows the configured resolvers without opening the admin console. It's the fastest way to spot a dead one.
- **`tailscale status`:** Shows `direct` versus `via DERP` on each peer, which separates transport problems from everything else.
- **`tailscale netcheck`:** Shows NAT type, port-mapping support and IPv6 availability.
- **Ping the tailnet address:** If a host answers on its Tailscale address but not its LAN address, the host is fine and its LAN address is the problem.

## Known quirks

- **IPv6 through the exit node:** The exit node advertises an IPv6 default route, but the ISP provides no IPv6, so IPv6-only sites hang. Dual-stack sites are unaffected. The two routes are a single toggle in the console, so this is accepted.
- **macOS Local Network permission:** One Mac could reach lab services over their tailnet addresses but not their LAN addresses, with `ERR_ADDRESS_UNREACHABLE` in the browser. `ping`, `curl` and Safari all worked. The cause was macOS's per-app **Local Network** privacy permission, which was off for that browser. macOS blocks the connection before it leaves the machine, which makes it look like a routing problem. The fix is enabling the permission and **fully quitting** the browser, since it's only read at launch.
- **Mac App Store CLI:** The CLI fails when called through a symlink. Use a shell alias to the binary inside the app bundle instead.
- **Serve and MagicDNS names:** A host's MagicDNS name can differ from its shell hostname. `tailscale serve status` shows the published URLs.

## Maintenance

- **Monthly:** Query both tailnet nameservers directly.
- **Quarterly:** Audit nodes, remove stale ones, and confirm key expiry is still disabled on infrastructure.
