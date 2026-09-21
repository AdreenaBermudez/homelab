# Incident log

Write-ups of real failures in the Casa Bermudez lab: what broke, how I diagnosed it, what fixed it, and what I changed afterward.

| Date | Incident | Area |
|---|---|---|
| 2026-07-27 | [Tailnet-wide DNS outage](2026-07-27-tailnet-dns-outage.md) | DNS, Tailscale |
| 2026-07-28 | [Docker failed to start after an OS image update](2026-07-28-docker-runc-missing.md) | Containers, immutable OS |
| 2026-08-01 | [Nightly backup stopped by its own safety guard](2026-08-01-backup-max-delete-trip.md) | Backups, alerting |
| 2026-08-09 | [Primary DNS Pi crashing every day or two](2026-08-09-pi-kernel-oops.md) | Linux kernel, hardware |
| 2026-08-25 | [New logins failing while existing sessions worked](2026-08-25-jellyfin-login-failure.md) | Application, database |
| 2026-09-11 | [The NUC declined its own IP address](2026-09-11-nuc-self-arp-conflict.md) | Networking |
