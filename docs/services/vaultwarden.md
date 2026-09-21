# Service: Vaultwarden

## What it does

A self-hosted, Bitwarden-compatible password manager. It works with the official Bitwarden apps and browser extensions, and it holds every credential in the lab.

## Deployment

| Item | Detail |
|---|---|
| Host | [NUC](../hosts/nuc-docker-host.md), Docker Compose |
| Image | `vaultwarden/server`, pinned to an exact version |
| Secrets | `.env` file, mode 600, never committed |
| Access | HTTPS on the tailnet only, through `tailscale serve`; Funnel is disabled |

## Why HTTPS through Tailscale

The Bitwarden clients and web vault require HTTPS, because browser cryptography APIs only work in secure contexts. `tailscale serve` provides a valid certificate on the tailnet hostname with no port forwarding, no reverse proxy and no public exposure. The same node also publishes ntfy, on a different port.

## Upgrade note: clients can outrun the server

The Bitwarden desktop app auto-updated to a release that showed an **empty vault** against Vaultwarden 1.36 and older. Nothing was lost; the newer clients simply need a newer server. Upgrading Vaultwarden to 1.37 fixed it.

**Rule:** When a Bitwarden client update causes strange behavior, check Vaultwarden's release notes before anything else.

## Backups

- **Before every upgrade:** A tarball of the data directory:
  ```bash
  sudo tar czf ~/vaultwarden-backup-$(date +%F).tar.gz -C <data-parent> data
  ```
- **Next step:** Add Vaultwarden's data directory to a nightly offsite job, the same way as the other services.

## Verified clients

iPhone autofill, the browser extension on macOS, and the desktop app.
