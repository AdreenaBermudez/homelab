# Runbook: Backup and restore

How the lab's backups work, how to confirm last night's runs succeeded, and how to restore each service.

---

## What gets backed up

| Job | Source | Destinations | Schedule |
|---|---|---|---|
| `nextcloud-backup` | Nextcloud web root, user data, MariaDB dump | Backblaze B2 + local copy on the Proxmox host (NFS) | Nightly 02:00 |
| `anytype-backup` | MinIO object storage for the Anytype sync server | Backblaze B2 | Nightly 02:30 |
| `ha-backup` | Home Assistant's own native backups | Backblaze B2 | Nightly 01:00 (HA writes a backup weekly) |
| Proxmox vzdump | All VMs and containers on the hypervisor | NFS storage on the NUC | Nightly |

- **Scheduling:** Every job runs from a systemd timer, not cron, so status and history live in the journal.
- **Separate buckets:** Each service has its own B2 bucket and its own application key scoped to that bucket, so one leaked key can't touch the others.

---

## Guards built into each job

- **Mount checks:** Each job verifies with `mountpoint -q`, plus a canary file, that the source and destination volumes are really mounted. A plain directory check passes on an empty mountpoint.
- **Size and file-count floors:** The job refuses to sync if the source is far below its normal size. Floors are set to about half the measured size.
- **Deletion limits:** `--max-delete` on every sync, so mass deletion stops the job instead of propagating to every copy.
- **Integrity checks:** The database dump must pass a minimum size and `gzip -t` before upload.
- **Post-upload verification:** Uses `rclone lsf` to confirm the dump reached B2, and compares remote and local object counts.
- **Freshness check (Home Assistant):** The newest backup must be under 10 days old. This catches HA's own scheduler dying silently while stale files keep uploading "successfully."
- **Failure alerting:** Every unit has an `OnFailure=` drop-in that sends a push notification. See [alerting](../services/alerting-ntfy-beszel.md).

---

## Daily check: did last night's backups succeed?

```bash
systemctl list-timers --all | grep -E 'backup'
systemctl status nextcloud-backup.service anytype-backup.service ha-backup.service --no-pager
```

- **Healthy:** Each service shows `status=0/SUCCESS` with a start time from the last 24 hours.
- **Check the log:** rclone writes straight to the log file, not the journal, so for the script's own summary lines use:

```bash
sudo grep -E 'Pre-flight|backup started|completed successfully|ERROR' /var/log/nextcloud-backup.log | tail -20
```

- **If a job failed:** The phone alert contains the exact `journalctl` command to run. Note the unit name in that command is doubled (`ntfy-failure@nextcloud-backup.service.service`). That's expected from the systemd template.

---

## Restore: Nextcloud

**Last full test:** June 2026. A complete restore from B2 recovered about 80 GB, 2,203 files and 74 folders.

1. **Put Nextcloud into maintenance mode and stop the app container.**
   ```bash
   docker exec -u www-data nextcloud-app php occ maintenance:mode --on
   docker compose -f ~/nextcloud/docker-compose.yml stop nextcloud-app
   ```
2. **Pull the files back from B2** into the data volume. Use `copy`, not `sync`, so nothing local is deleted by mistake.
   ```bash
   rclone copy <b2-remote>:<nextcloud-bucket> /var/mnt/data/nextcloud/data --progress
   ```
3. **Restore the most recent database dump** into the MariaDB container.
   ```bash
   gunzip -c <latest-dump>.sql.gz | docker exec -i nextcloud-db mariadb -u <db-user> -p<db-password> <db-name>
   ```
4. **Start Nextcloud, rescan files and clear maintenance mode.**
   ```bash
   docker compose -f ~/nextcloud/docker-compose.yml start nextcloud-app
   docker exec -u www-data nextcloud-app php occ files:scan --all
   docker exec -u www-data nextcloud-app php occ maintenance:data-fingerprint
   docker exec -u www-data nextcloud-app php occ maintenance:mode --off
   ```
5. **Verify:** `occ status` shows the expected version and `needsDbUpgrade: false`, and a desktop client syncs.

**Gotcha:** `find` and `du` on the Nextcloud data directory need `sudo`, because the inner `data/` directory is owned by root. Without `sudo`, counts come back misleadingly low.

---

## Restore: Anytype object storage

**Last test:** July 2026. All 1,781 files were pulled back from B2 to a scratch folder and matched the live data.

1. **Test restore to scratch first.** This proves the backup without touching production.
   ```bash
   rclone copy <b2-remote>:<anytype-bucket> /tmp/anytype-restore-test --progress
   ```
   Confirm that `minio-bucket/` and `.minio.sys/` are both present.
2. **Real restore:** Stop the Anytype stack on its VM (`sudo make stop`), copy the data back into the MinIO NFS export, then start the stack (`sudo make start`) and confirm that every service reports healthy.

**Note:** Anytype has only two copies, the live data and B2. That makes the deletion guards on its sync matter even more than Nextcloud's.

---

## Restore: Home Assistant

**Status:** The backup chain is verified end to end. A full restore has not been tested yet.

1. **Download the newest backup** from B2.
   ```bash
   rclone copy <b2-remote>:<ha-bucket>/backups /tmp/ha-restore --max-age 14d
   ```
2. **Restore through HA itself:** Settings → System → Backups → Upload backup → Restore.
3. **Expect empty history graphs.** The recorder database is deliberately excluded from backups, so configuration, users and integrations come back but graphs start fresh.

---

## Restore: a Proxmox VM

1. **In the Proxmox UI:** Go to the NFS backup storage → Backups, select the VM's most recent archive, and choose **Restore**.
2. **For a test,** restore to a new VM ID so the original stays untouched. Boot it with its network disconnected and confirm it starts.

---

## Maintenance

- **Recalibrate the floors** when a dataset grows substantially. Re-measure the source and set the floors to about half of it.
- **Quarterly key rotation:** Rotate every B2 application key and the ntfy token.
- **Known gap:** The B2 syncs are mirrors, so an accidental file deletion propagates offsite the next night. Database dumps keep 7 days of history; file data has no grace period yet. Enabling B2 object versioning is on the roadmap.
