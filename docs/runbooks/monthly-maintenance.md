# Runbook: Monthly maintenance

The recurring checklist that keeps the lab patched and proves that its safety nets still work. Each item exists because something once broke or nearly broke.

---

## 1. Reboot the NUC and verify everything auto-starts

1. **Reboot, then confirm Docker came up:** `systemctl status docker --no-pager`.
   - **Watch for:** `exec: "runc": executable file not found`. That means an OS image update dropped the runtime again. See the [runc incident](../incidents/2026-07-28-docker-runc-missing.md).
2. **Check containers:** `docker ps --format 'table {{.Names}}\t{{.Status}}'`. Every container should be `Up`, and ones with healthchecks should show `(healthy)`.
3. **Check Tailscale:**
   - `tailscale status`: the node should be present and not `offline`. `idle` is normal.
   - `tailscale serve status`: both HTTPS services should be listed (Vaultwarden and ntfy).
   - From a client, run `tailscale ping` against the NUC.
   - The health warning `--accept-routes is false` is expected on this host.
4. **Send a test alert** with the shared `ntfy-alert` script and confirm it arrives on the phone.
5. **Load the web UIs:** Beszel, Vaultwarden, Homepage and Home Assistant.

---

## 2. Update the NUC's Docker stacks

Every image is pinned to a version, so updates are deliberate.

1. **Pick the new version** from the project's release notes. Read the breaking changes first.
2. **Back up the compose file**, then change the tag.
   ```bash
   cp docker-compose.yml docker-compose.yml.bak-$(date +%F)
   ```
3. **Validate the file:** `docker compose config --quiet` should print nothing.
4. **Apply the update to one service:**
   ```bash
   docker compose pull <service>
   docker compose up -d --force-recreate <service>
   ```
5. **Verify the running image** actually changed:
   ```bash
   docker inspect <service> --format '{{.Config.Image}}'
   ```

**Rules learned the hard way:**
- **`docker compose up -d` can report "Started" without applying a config change.** Use `--force-recreate` and verify with `docker inspect`.
- **Nextcloud can't skip major versions.** It's pinned to its major version (`nextcloud:33`), so patches arrive automatically but a major jump is always a deliberate, one-step-at-a-time upgrade. Take a backup first.
- **`env_file` values are read only when the container is created.** A plain restart won't pick up a changed variable.

---

## 3. Update the Proxmox host

1. **Update packages:** `apt update && apt full-upgrade`.
2. **Update Jellyfin** with the same pinned-image procedure as above.
3. **After any NUT package update,** confirm that NUT is still **masked**. See the [UPS runbook](ups-lost-communication.md).

---

## 4. Pi-hole and Pi OS maintenance (both DNS nodes)

1. **Confirm both tailnet nameservers answer.** This is the check that would have caught the [tailnet DNS outage](../incidents/2026-07-27-tailnet-dns-outage.md) early.
   ```bash
   dig @<pi1-tailnet-address> example.com +short
   dig @<pi2-tailnet-address> example.com +short
   ```
2. **Update Pi-hole:** `pihole -up`.
3. **Update the OS inside `tmux`:** `sudo apt update && sudo apt full-upgrade`. If a node crashes mid-upgrade, run `sudo dpkg --configure -a` **before** rebooting.
4. **Refresh blocklists:** `pihole -g`. Every list should be healthy, and both nodes should carry the same lists.
5. **Leave `tailscaled` running on both Pis.** It's load-bearing for tailnet DNS.

---

## 5. Storage and backup verification

1. **Check disk usage** in Beszel or the Homepage header for every drive, including the external ones.
2. **Confirm last night's backups** using the daily check in the [backup runbook](backup-and-restore.md).
3. **Check the Proxmox VM backups** in the Proxmox UI: the newest archive for each VM should be under 24 hours old.
4. **Run the storage canary** by hand:
   ```bash
   sudo systemctl start check-media-mount.service
   systemctl status check-media-mount.service --no-pager
   ```
   It should exit 0 and send no alert.

---

## 6. Prove that alerting still fires end to end

1. **Stop a monitoring agent** on a non-critical host (for example, the secondary Pi) and **wait at least 6 minutes.** Alerts have a 5-minute delay, so a quick stop-and-start proves nothing.
2. **Confirm** the "down" notification arrives on the phone.
3. **Restart the agent** and confirm the "recovered" notification.

---

## 7. UPS self-test

1. **Run** `pwrstat -test` on the Proxmox host, then `pwrstat -status`.
2. **Confirm** the result is "Passed" and the load reading is plausible (about 40–50 W for this setup). A 0 W reading right after a USB reconnect is a known false reading. See the [UPS runbook](ups-lost-communication.md).

---

## Less frequent tasks

| Cadence | Task |
|---|---|
| Quarterly | Router firmware update |
| Quarterly | Rotate B2 application keys and the ntfy token |
| Quarterly | Tailscale node audit: remove stale nodes and confirm key expiry is disabled on infrastructure nodes |
| Every 6 months | SMART check on every hard drive |
| Every 6 months | Real power test: pull the UPS's mains plug for about 15 seconds and confirm everything stays up |
| Every 6 months | Nextcloud storage review |
