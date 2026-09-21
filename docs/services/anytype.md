# Service: Anytype (self-hosted sync)

## What it does

Anytype is a local-first notes app. By default, devices sync through Anytype's public network. This deployment runs the whole sync backend (`any-sync`) in the lab, so notes sync between the Macs and iPhone without touching a third-party server.

## Deployment

| Item | Detail |
|---|---|
| Host | Dedicated VM on the [Proxmox host](../hosts/proxmox-host.md): Ubuntu 24.04, 4 GB RAM, 2 cores |
| Stack | The upstream `any-sync-dockercompose` project: sync nodes, coordinator, MongoDB, Redis, MinIO |
| Access | LAN and tailnet. The VM runs Tailscale, and the generated client config lists both addresses |
| Login | SSH key-only |

## Storage design

- **Why split storage:** The VM's disk is small. MinIO, the object store for attachments, is the part that grows with use.
- **What moved:** Only MinIO's directory lives on an NFS export from the NUC. MongoDB and Redis stay on the VM's local disk, because databases on NFS risk file-locking and performance problems.
- **How:** The project uses one `STORAGE_DIR` for every service, so I didn't redirect it. Instead, I stopped the stack, `rsync`ed the MinIO data to the NFS mount, and replaced just `storage/minio` with a symlink. All services came back healthy.
- **VM CPU type:** Set to `host`, because MongoDB needs AVX, which the default virtual CPU doesn't expose.

## Backups

- **Nightly:** MinIO data goes to its own B2 bucket with a bucket-scoped key.
- **Guards:** A mount check, MinIO structure markers (`.minio.sys` and the bucket directory must both exist), file and size floors, `--max-delete`, and a remote object count compared to local afterward.
- **Tested:** A restore to a scratch directory pulled back every file.
- **Known noise:** MinIO rewrites a usage-cache file during the sync, so rclone sometimes logs a hash mismatch and succeeds on retry. It's harmless, since that cache regenerates automatically.

## Gotchas

- **"Select vault error" when joining a device:** Caused by stale local state from an earlier failed attempt. Fully deleting and reinstalling the app fixed it; logging out didn't.
- **Load the network config first.** On a new device, load the self-hosted `client.yml` **before** taking any account action.
- **Refreshing the config is easy.** Reloading an updated `client.yml` while logged in doesn't require logging out.
