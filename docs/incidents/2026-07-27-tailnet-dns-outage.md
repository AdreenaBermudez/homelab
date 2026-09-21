# Incident: Tailnet-wide DNS outage

**Date:** July 27–28, 2026
**Impact:** Browsing hung or crawled on every device while Tailscale was connected, at home and remotely
**Status:** Resolved

---

## Summary

Every device on the tailnet uses Tailscale's MagicDNS, with "Override local DNS" enabled so that tailnet-configured nameservers take priority over whatever DHCP hands out. Both of the configured global nameservers had quietly died. MagicDNS had no working upstream, so name resolution failed for every device connected to Tailscale, while the network itself was fine.

## Symptoms

- **Remote:** The internet appeared to drop whenever Tailscale connected.
- **At home:** Connections dropped or ran extremely slowly with Tailscale on.
- **Intermittent in clusters:** A resolver loop test caught four consecutive failures within 12 seconds, while other queries minutes earlier had succeeded. The successes turned out to be cache hits inside `tailscaled`, which made the fault look random.

## Investigation

1. **Transport ruled out.** `tailscale netcheck` showed UDP working, easy NAT, and all port-mapping protocols available on the router. The nearest relay responded in under 20 ms.
2. **Narrowed to DNS.** With the exit node on, `curl` failed with "Resolving timed out after 10006ms" and `dig` reported that no servers could be reached. Raw connectivity was fine.
3. **Found the resolver order.** `scutil --dns` on macOS showed Tailscale's resolver (`100.100.100.100`) ranked above the local Pi-hole resolvers. That is expected with Override on, but it meant every query depended on MagicDNS.
4. **Found the root cause.** `tailscale dns status` listed the tailnet's configured nameservers. Both were dead:
   - **One** pointed at an address that no longer matched any node. It was a stale registration left over from when a Pi-hole node rejoined the tailnet with a new identity.
   - **The other** was the secondary Pi-hole node. I had disabled `tailscaled` on it two days earlier to reclaim RAM on a memory-constrained Pi, without realizing that removed it from tailnet DNS.

## Root cause

The tailnet's DNS configuration depended on two nameservers, and both became unreachable through separate, unrelated changes. Nothing alerted on it because nothing was monitoring whether the tailnet's resolvers answered.

## Fix

- **Immediate:** In the Tailscale admin console, replaced the dead entries with the primary Pi-hole's current tailnet address. Verified with `dig @100.100.100.100` returning real records.
- **Redundancy restored:** Re-enabled `tailscaled` on the secondary Pi and added it back as a second nameserver. The memory cost was about 12 MB, far less than the savings I had assumed when I disabled it.
- **Considered and rejected:** Advertising the LAN subnet from the NUC instead. That would have concentrated the exit-node and DNS roles on one machine.

## Follow-up

- **Load-bearing service documented:** `tailscaled` on both Pi-hole nodes is now marked as required for tailnet DNS in my notes.
- **Monthly check added:** A maintenance task queries both tailnet nameservers directly.
- **Quarterly check added:** A node audit removes stale registrations before they end up in configuration.
- **Known quirk documented:** The exit node advertises an IPv6 default route, but my ISP provides no IPv6, so IPv6-only destinations hang. I measured it, confirmed dual-stack sites are unaffected, and accepted it.

## Lessons

- **"Saving resources" on a node can remove a role it quietly performs.** Before disabling a service, check what depends on it.
- **`tailscale dns status` is the fastest way to find a dead resolver.** It shows the configured nameservers without opening the admin console.
- **Cache hits make a total DNS failure look intermittent.** A single successful query proves very little.
