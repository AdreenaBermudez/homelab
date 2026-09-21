# Hosts: Raspberry Pi DNS nodes

## Role

A two-node DNS layer for the home network and the tailnet. The primary is a Raspberry Pi 4 on Ethernet; the secondary is a lower-memory Pi on Wi-Fi. Both run [Pi-hole with Unbound](../services/pihole-unbound.md).

- **Both nodes:** Each is a configured nameserver for the tailnet. The router's DHCP hands out only these two addresses.
- **Primary only:** Also advertises the home LAN as a Tailscale subnet route.

## Configuration choices

- **Headless trimming (secondary):** The secondary has about 425 MB of RAM and was shipped running a full desktop it never used. I disabled the display manager, remote-desktop server, printing, Bluetooth, ModemManager and other unused services, and set the boot target to `multi-user.target`. Memory use dropped from 262 MiB to 222 MiB.
- **Load-bearing `tailscaled`:** It must not be disabled on either node for memory savings. Disabling it on the secondary caused the [tailnet DNS outage](../incidents/2026-07-27-tailnet-dns-outage.md).
- **Persistent journal:** Raspberry Pi OS ships a drop-in that keeps the journal in RAM (`Storage=volatile`), so logs vanish on reboot. A higher-priority drop-in sets `Storage=persistent` with a 100 MB cap.
- **Time sync:** `systemd-timesyncd` owns upstream time sync. Pi-hole's own NTP *client* is disabled to stop the two from conflicting, while Pi-hole still *serves* NTP to LAN clients.
- **Monitoring:** The Beszel agent is installed as a binary and systemd service, since these nodes don't run Docker. Alerts are set for node down, and for memory on the secondary.

## Crash instrumentation (primary)

Built during the [kernel oops investigation](../incidents/2026-08-09-pi-kernel-oops.md) and kept in place afterward:

- **Hardware watchdog:** Runtime 1 minute, reboot 2 minutes, so a hang recovers unattended.
- **Remote syslog:** All logs go to the Proxmox host, so crash evidence survives the crash. Journald and rsyslog rate limits are lifted.
- **netconsole:** Sends kernel messages from kernel context over UDP, so it survives a panic. It's made persistent with a systemd unit.
- **Throttle logging:** `vcgencmd get_throttled` is logged every minute, which gives a continuous record for ruling out power problems.

## Gotchas

- **Remote logs:** Crash logs forwarded here use ISO-8601 timestamps and can contain NUL bytes from the crash, so `grep` treats them as binary. Use `grep -a`.
- **netconsole lines:** They arrive with no hostname field. Search by the sender's IP.
- **Testing netconsole:** A plain write to `/dev/kmsg` is below the console log level and never reaches netconsole. Test with an explicit priority prefix: `echo "<0>test" | sudo tee /dev/kmsg`.
- **Crash mid-upgrade:** If a node crashes during `apt full-upgrade`, don't reboot. Run `dpkg --configure -a` first, then re-run the upgrade inside `tmux`.
