# Incident: The NUC declined its own IP address

**Date:** September 11, 2026
**Impact:** Every service on the NUC was unreachable at its LAN address; the host stayed reachable over Tailscale
**Status:** Resolved

---

## Summary

The NUC has both wired and wireless network adapters. Its Wi-Fi profile auto-connected and took a second address on the LAN. When the wired adapter later ran DHCP's duplicate-address check for its reserved address, the NUC's own Wi-Fi adapter answered the ARP probe. NetworkManager concluded the address was already in use and declined the lease, leaving the wired adapter with no IPv4 address at all.

## Symptoms

- **Browser errors:** Pages failed with `ERR_ADDRESS_UNREACHABLE`.
- **Ping from macOS:** Returned "Host is down," which points to ARP failure rather than a refused port.
- **Tailscale unaffected:** The host was reachable at its Tailscale address the whole time.

## Investigation

1. **Split the problem using Tailscale.** The host was reachable over the tailnet but not the LAN, so it was up and healthy; only its LAN address was missing.
2. **Checked the link.** The wired adapter showed carrier at 1000 Mb/s full duplex, but no IPv4 address.
3. **Read NetworkManager's logs.** They showed a conflict for the reserved address, attributed to a MAC address belonging to the NUC's own Wi-Fi adapter. They also showed the mirror-image conflict on the Wi-Fi's address, attributed to the wired adapter's MAC.

## Root cause

- **Two adapters on one subnet:** With both connected to the same LAN, the host's own interfaces answered each other's duplicate-address probes.
- **Why a router reservation couldn't help:** The Wi-Fi adapter used a randomized MAC, so it could never have matched a DHCP reservation.

## Fix

- **Disabled Wi-Fi autoconnect:** `nmcli con mod "<wifi-profile>" connection.autoconnect no`
- **Recovered the address:** Brought the Wi-Fi connection down and cycled the wired one. The wired adapter took its reserved address back.
- **No container restarts were needed.**

## Lessons

- **Ping the Tailscale address first.** It's the fastest way to separate "host is down" from "host is fine, its LAN address is gone."
- **"Host is down" on macOS means ARP failed.** Look at layer 2 before looking at the service.
- **Keep infrastructure hosts on one interface per subnet** unless there's a deliberate reason for more.
- **Related gotcha, same week:** Backgrounding a `sudo` command with `&` detaches it from the terminal, so the password prompt can't hide input and the typed password lands in the shell as a command. For commands that will cut off their own SSH session, run `sudo -i` alone first, then use `systemd-run`.
