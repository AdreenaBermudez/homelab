# Host: Intel NUC (Docker host)

## Role

The lab's main container host and storage hub. It also runs the backup jobs, acts as the NFS server, and serves as the Tailscale exit node and a subnet router.

## Hardware and OS

| Item | Detail |
|---|---|
| Machine | Intel NUC 10 (NUC10i5FNH) |
| CPU / RAM | Intel Core i5-10210U, 8 GB |
| OS disk | 256 GB NVMe |
| Service data | 1 TB internal HDD |
| External | 18 TB media drive (USB), 2 TB drive for object storage (USB) |
| OS | Bazzite, an immutable Fedora Atomic image, with SELinux enforcing |

## What runs here

All in Docker Compose, one directory per stack:

- **[Nextcloud](../services/nextcloud.md)** with MariaDB
- **[Vaultwarden](../services/vaultwarden.md)**
- **[Home Assistant](../services/home-assistant.md)**
- **[Homepage](../services/homepage.md)**, **Beszel** hub and **Portainer** in the monitoring stack
- **ntfy** for push alerts. See [alerting](../services/alerting-ntfy-beszel.md).

## Working with an immutable OS

- **Layered packages:** `/usr` is read-only, and extra packages are layered with `rpm-ostree`. Docker, `runc` and the game-streaming server are layered; everything else runs in containers.
- **`runc` must stay layered.** An image update once dropped it and took Docker down. See the [incident](../incidents/2026-07-28-docker-runc-missing.md).
- **Paths:** Writable installs go in `/usr/local`. Data mounts live under `/var/mnt`, not `/mnt`.
- **The `docker` group:** On this image, the group is defined in `/usr/lib/group`, not `/etc/group`. As a result, `groupadd` refuses ("already exists") and `usermod -aG` silently does nothing. The fix was adding the group entry to `/etc/group` with the **same GID** as the socket's group ownership.

## SELinux

- **Labeling bind mounts:** Every directory bind-mounted into a container needs the container file label, or the container gets permission errors:
  ```bash
  sudo chcon -Rt svirt_sandbox_file_t <path>
  ```
- **Exceptions:** A few containers use `security_opt: label:disable`, for example ones that need the Docker socket. Each is a deliberate, documented exception, not a default.

## Storage design

- **Drive roles:** The 1 TB HDD holds service data (Nextcloud, Vaultwarden, Home Assistant, ntfy, monitoring). The 18 TB drive holds media only. Media is replaceable, so it has no RAID; irreplaceable data gets offsite backups instead.
- **18 TB filesystem:** ext4 with `-T largefile` (fewer inodes for large files) and `-m 1`. Mounted with `nofail,x-systemd.device-timeout=30`, so a missing drive can't stall boot.
- **Dropout guards:** A USB drive that disappears leaves an empty mountpoint, and a container writing into it fills the OS disk. So:
  - **Immutable mountpoint:** The underlying directory is `chattr +i`, so nothing can write to it while unmounted.
  - **Docker waits for the mount:** A systemd drop-in adds `RequiresMountsFor=` to `docker.service`.
  - **Canary check:** A systemd timer checks the mount and a canary file every 15 minutes and sends an alert if either is missing.
- **USB bridge quirks:** This enclosure's USB-to-SATA bridge needs `smartctl -d sat` and can't answer SMART queries while the drive is busy. Extended self-tests aborted at the same point twice. Instead, I used the full initial data copy as a burn-in and compared SMART attributes before and after. All were clean.
- **Chose not to force UAS.** The drive runs on the older `usb-storage` driver. The kernel has known UAS quirks for this bridge family, and the one-time speed gain wasn't worth the risk of lockups.
- **Heat:** The fanless enclosure reached 52 °C during sustained writes. That's a factor in where it sits in the planned rack.

## Networking

- **Exit node and subnet router:** The NUC advertises the home LAN as a subnet route alongside the primary DNS Pi, so LAN access over the tailnet survives either one going down.
- **HTTPS to the tailnet:** Vaultwarden and ntfy are published with `tailscale serve`, never Funnel. See [Tailscale](../services/tailscale.md).
- **Wired only:** The Wi-Fi profile has autoconnect disabled after the host [declined its own IP address](../incidents/2026-09-11-nuc-self-arp-conflict.md).

## Related

- [Backup and restore](../runbooks/backup-and-restore.md)
- [Monthly maintenance](../runbooks/monthly-maintenance.md)
