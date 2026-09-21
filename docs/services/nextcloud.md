# Service: Nextcloud

## What it does

File sync for the household's Macs, Windows laptop and phones. It's a self-hosted replacement for iCloud Drive and Dropbox.

## Deployment

| Item | Detail |
|---|---|
| Host | [NUC](../hosts/nuc-docker-host.md), Docker Compose |
| Images | `nextcloud:33` (pinned to the major version) + `mariadb:10.11` |
| Data | The whole web root is bind-mounted from the 1 TB service-data drive |
| Access | LAN and tailnet only; nothing exposed to the internet |

## Why it's pinned to a major version

Nextcloud can't skip major versions: 33 → 34 → 35 must happen one at a time. With a floating `latest` tag, a pull that lands two majors ahead leaves a container that won't start. Pinning to `nextcloud:33` lets patch releases arrive automatically, while every major upgrade is a deliberate step with a backup taken first.

## Backups

The most heavily guarded job in the lab. It runs nightly and does the following:

1. **Enables maintenance mode,** with an `EXIT` trap that always turns it off again.
2. **Dumps the database** and checks the dump's size and `gzip` integrity.
3. **Runs pre-flight checks:** mounts, file-count and size floors, and both containers running.
4. **Syncs to Backblaze B2** with `--max-delete`, and verifies that the dump landed.
5. **Syncs to a local copy** on another host over NFS.

Full details and the restore procedure are in the [backup runbook](../runbooks/backup-and-restore.md). A full 80 GB restore from B2 has been tested.

## Lessons

- **The backup mirrors application code too,** so a patch upgrade shows up as hundreds of deletions. That's what tripped the [max-delete guard](../incidents/2026-08-01-backup-max-delete-trip.md) the night after an upgrade.
- **The container runs the upgrade itself.** On an image upgrade, the entrypoint updates the database schema and turns maintenance mode off automatically. Verify afterward with `occ status` (`needsDbUpgrade: false`).
- **Size data with `sudo`.** The inner `data/` directory is owned by root, so `find` and `du` without `sudo` report misleadingly low numbers.
