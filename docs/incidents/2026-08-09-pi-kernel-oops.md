# Incident: Primary DNS Pi crashing every day or two

**Dates:** Late July – August 9, 2026 (investigation); resolved by kernel upgrade
**Impact:** The primary Pi-hole node, which is also a tailnet nameserver and subnet router, rebooted itself roughly nine times in eight days
**Status:** Resolved — no crashes since the kernel upgrade

---

## Summary

A Raspberry Pi 4 running Pi-hole and Unbound kept crashing and recovering through its hardware watchdog. Power, storage and the network were each ruled out with evidence. Crash data captured from kernel context traced the problem to the Pi 4's onboard Ethernet driver passing corrupted packets up the IPv6 receive path. A kernel upgrade resolved it.

## Symptoms

- **Silent reboots:** The node restarted every day or two, usually without anyone noticing, because the watchdog recovered it.
- **One network wedge:** On one occasion it stayed powered on but stopped answering on the LAN. The link stayed up while ARP to hosts on the same subnet failed.
- **No local evidence:** The node's own logs were lost with each crash.

## Investigation

**Ruling things out:**

- **Power:** I logged the Pi's throttle and undervoltage flags every minute for a week. All 9,411 samples were clean, including right after crashes. I also swapped in a new power supply and the crashes continued.
- **SD card:** The filesystem superblock showed a clean state with no ext4 errors, and the node had run for days at a time on the same card.
- **Router and cable:** The router had 12+ days of uptime across the period, with no link events or carrier loss on the Pi's port.

**Capturing the crash:**

- **Remote syslog:** I forwarded everything to a central collector on the Proxmox host and lifted journald and rsyslog rate limits. This captured the start of each crash.
- **Its limit:** Remote syslog is a userspace process, and the kernel stops scheduling within milliseconds of a fatal oops, so only the first dozen lines ever arrived.
- **netconsole:** To get the full trace, I set up netconsole, which transmits kernel messages from kernel context over UDP and survives a panic. I made it persistent with a systemd unit.

**What the evidence showed:**

- **Eight kernel oopses** against about nine restarts. They were memory-access faults at wild and null addresses, not power loss.
- **One complete call trace** ran from `bcmgenet_rx_poll`, the Pi 4 Ethernet driver's receive path, through IPv6 netfilter connection tracking, into `netdev_rx_csum_fault`. The NIC's hardware checksum offload was passing packets that the kernel then recomputed as corrupt, and the packet buffer held unrelated memory.

## Root cause

A fault in the Ethernet driver's receive path on that kernel version corrupted packet buffers. The node crashed whenever a bad buffer was dereferenced.

## Fix

- **Kernel upgrade:** Upgraded the kernel and kept it as the only change during a watch window, so the result would be attributable.
- **Watchdog:** A hardware watchdog (1-minute runtime, 2-minute reboot) stayed in place as a safety net for unattended recovery.
- **Documented fallback:** If the crashes ever return, the next step is disabling receive checksum offload with `ethtool -K eth0 rx off`, made persistent with a systemd unit.

**Result:** After roughly nine crashes in eight days, the node has not crashed once since the upgrade.

## Side note: recovering from a crash mid-upgrade

The node crashed during the `apt full-upgrade` itself, leaving the new kernel, firmware and systemd unpacked but not configured. Rebooting in that state risks an unbootable system. The safe sequence was:

1. `dpkg --configure -a`
2. `apt -f install`
3. Re-run the upgrade inside `tmux`, so a dropped session or another crash couldn't interrupt it.

## Lessons

- **Rule out the cheap explanations with data, not assumptions.** A week of throttle logs settled the power question conclusively.
- **Userspace logging can't record a kernel's last words.** netconsole can.
- **Change one variable at a time during a watch window,** or you won't know what fixed it.
