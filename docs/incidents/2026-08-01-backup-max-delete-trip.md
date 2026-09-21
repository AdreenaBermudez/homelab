# Incident: Nightly backup stopped by its own safety guard

**Date:** August 1, 2026
**Impact:** One night's offsite and local Nextcloud backup was skipped; no data was lost and Nextcloud stayed online
**Status:** Resolved

---

## Summary

The day before, I had hardened the Nextcloud backup script with several guards, including an rclone `--max-delete` limit. The next night, the limit tripped on legitimate changes from a Nextcloud patch upgrade. The job failed, the alerting chain paged my phone, and the failure-safety trap kept Nextcloud out of maintenance mode. It was the first real-world test of both safeguards.

## Background: why the guard exists

The backup mirrors Nextcloud's data directory to Backblaze B2 and then to a local copy on another host. If the source drive ever fails to mount, `rclone sync` would see an empty directory and faithfully delete everything in both copies in a single night. To prevent that, the hardened script:

- **Checks mounts:** Confirms both the data and backup volumes are really mounted.
- **Enforces floors:** Refuses to run if the source is suddenly far below its normal file count or size.
- **Limits deletions:** Passes `--max-delete` so that mass deletion stops the sync instead of propagating.
- **Always cleans up:** Uses an `EXIT` trap that takes Nextcloud out of maintenance mode even if the script fails partway through.

## Timeline

- **July 31:** Upgraded Nextcloud 33.0.5 to 33.0.7 and deployed the hardened script with `--max-delete 500`.
- **August 1, 02:00:** The nightly timer started the job. All pre-flight checks passed.
- **02:26:** The rclone sync to B2 logged exactly 500 deletions, then stopped: "max-delete threshold reached." The script exited with a non-zero code.
- **02:26:** The systemd `OnFailure=` handler sent a push notification to my phone with the `journalctl` command needed to investigate.

## Investigation

1. **Counted the deletions in the log.** There were exactly 500 "Deleted" lines for that run, followed by errors on the next eight files. The guard had done exactly what it was written to do.
2. **Identified the files.** They were hashed JavaScript and CSS assets inside Nextcloud's app directories.
3. **Connected it to the upgrade.** The backup mirrors the entire web root, including application code, not just user files. A patch upgrade replaces hundreds of hashed asset filenames, which produced about 508 deletions in total.
4. **Confirmed the trap worked.** `occ status` showed maintenance mode off, so users were never locked out.

## Root cause

The `--max-delete` threshold was set below the normal churn caused by an application upgrade. It was a calibration error, not a script bug.

## Fix

- **Raised the limit from 500 to 5,000.** That still trips on genuine mass deletion against a dataset of about 29,000 files, while absorbing upgrade churn.
- **Kept the floors as the primary defense.** The file-count and size floors run before rclone starts and are what actually stop the unmounted-volume scenario. `--max-delete` is defense in depth.
- **Verified:** A manual run completed successfully, including the local copy and the post-upload check that the database dump landed in B2.

## Lessons

- **Test guards against real events, not just synthetic ones.** This failure proved the alerting chain and the cleanup trap under real conditions.
- **Calibrate thresholds from measurements.** The same calibration pass also caught a database-dump size floor I had initially set above the real dump size, which would have failed every night.
- **Know what your backup actually covers.** Mirroring application code alongside data means upgrades show up as deletions.
