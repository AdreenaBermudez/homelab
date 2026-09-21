# Service: Pi-hole + Unbound

## What it does

Network-wide ad and tracker blocking for every device on the LAN and the tailnet, with recursive DNS resolution that doesn't depend on the ISP's resolvers.

```
Client → Pi-hole (:53) → Unbound (:5335) → root and authoritative servers
```

## Deployment

| Item | Detail |
|---|---|
| Hosts | Two [Raspberry Pi nodes](../hosts/pi-dns-nodes.md), primary and failover |
| Version | Pi-hole v6 |
| Resolver | Unbound on each node, with DNSSEC validation and `edns-buffer-size: 1232` |
| Blocklists | Four, the same on both nodes: StevenBlack, Hagezi Pro, OISD Basic, Peter Lowe's (about 464,000 unique domains) |

## Making sure clients actually use it

- **The bypass I found:** The router's DHCP DNS fields were blank, so it handed out *itself* as the DNS server and forwarded queries straight to the ISP, skipping Pi-hole for many devices. A DNS leak test and `scutil --dns` revealed it.
- **The fix:** DHCP now hands out only the two Pi-holes, and the router's "advertise router's IP in addition" option is off, so clients can't pick the unfiltered path.
- **Verified:** `dig` against a known ad domain, with no server specified, returns `0.0.0.0`.
- **Tailnet devices:** They reach the same Pi-holes, which are configured as the tailnet's global nameservers.

## Per-device exceptions: key them by MAC, not IP

The TV needs unfiltered DNS for its streaming apps. The exception was originally keyed to the TV's IP address. When DHCP reshuffled addresses, a phone configured with that same static IP quietly inherited the TV's unfiltered access. Now:

- **The exception is keyed to the TV's MAC address,** so an address change can't hand it to another device.
- **The phone was moved to DHCP,** which also fixed a wrong subnet prefix it had been set with.
- **Limit:** MAC matching only works for devices at most one network hop from the Pi-hole.

## Gotchas

- **Groups aren't synced between nodes.** A group created on the primary must be created on the secondary too.
- **Blocklist URLs with query strings:** Pi-hole splits the address field on spaces and commas. A URL containing `&` was broken into fragments, one of which downloaded an HTML page as a "blocklist." Paste such URLs whole and check the parsed domain count.
- **Query log searches:** To search more than the last 24 hours, tick "Query on-disk data." The client-name filter matches hostnames only; use the IP filter for addresses.
- **The rate limit is global,** not per client.
- **No more `pihole restartdns` in v6.** Use `sudo systemctl restart pihole-FTL`.
- **Widget and API passwords:** Keep passwords that other tools use for the API plain alphanumeric. A `$` in the password broke the [Homepage](homepage.md) widget, even though it authenticated fine with `curl`.

## Next steps

- **Block DNS bypass:** DNS-over-HTTPS and DNS-over-TLS can skip Pi-hole. The plan is a DoH/VPN bypass blocklist first, then browser settings; blocking ports 53 and 853 at the router is deferred.
