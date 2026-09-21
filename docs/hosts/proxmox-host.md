# Host: Proxmox VE hypervisor

## Role

The lab's hypervisor. It runs the Linux VMs, hosts Jellyfin, monitors the UPS, and collects remote logs from the DNS nodes.

## Hardware and OS

| Item | Detail |
|---|---|
| Machine | GMKtec G3 Pro mini PC |
| CPU | Intel Core i3-10110U (2 cores / 4 threads) |
| OS | Proxmox VE, installed on the internal drive with LVM |
| Extra storage | 1 TB USB SSD (ext4), used as a local backup target and staging space |
| Power | On the UPS's battery-backed outlets; the UPS reports to this host over USB |

## What runs here

- **Anytype sync server VM:** Ubuntu Server 24.04, 4 GB RAM, 2 cores. The CPU type is set to `host`, because MongoDB needs AVX instructions that the default virtual CPU doesn't expose. See [Anytype](../services/anytype.md).
- **Jellyfin:** Runs in Docker directly on the host, with its libraries bind-mounted in. Some media is served from the NUC over NFS.
- **UPS monitoring:** `pwrstatd` is the only UPS monitor. See the [UPS runbook](../runbooks/ups-lost-communication.md).
- **Central syslog collector:** Receives remote syslog and netconsole traffic from the primary DNS node. That's what captured the [Pi kernel oops](../incidents/2026-08-09-pi-kernel-oops.md).
- **Beszel agent:** Runs in Docker and reports host metrics, including the USB SSD as an extra filesystem.

## Storage and NFS

- **As an NFS client:** Nightly VM backups (vzdump) go to NFS storage on the NUC. The backups live on a different machine from the VMs they protect.
- **As an NFS server:** I installed `nfs-kernel-server` (Proxmox ships only the client) and export the USB SSD back to the NUC as the local target for the Nextcloud backup.
- **Reserved space:** The USB SSD was reformatted to ext4 with `tune2fs -m 1`. That drops the root-reserved space from 5% to 1%, since the disk holds no system files.

## Design decisions

- **Keep bulk data off the OS disk.** Early on, the Jellyfin library lived on the same LVM root volume as the VM disks, so filling it could have taken the hypervisor down. I moved media off the root disk. Large libraries now live on dedicated external storage.
- **Know how bind mounts behave.** Docker bind mounts are private by default, so a filesystem mounted *underneath* an existing bind mount isn't visible to the container until it restarts. After adding a submount, `docker restart jellyfin` is required.
- **Filesystem work needs the Beszel agent stopped.** Formatting the SSD failed with "apparently in use by the system" because the monitoring agent's container held a bind mount of it. `docker stop beszel-agent` released it.

## Related

- [Monthly maintenance: updating the Proxmox host](../runbooks/monthly-maintenance.md#3-update-the-proxmox-host)
- [Backup and restore: restoring a Proxmox VM](../runbooks/backup-and-restore.md#restore-a-proxmox-vm)
