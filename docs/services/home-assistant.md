# Service: Home Assistant

## What it does

Smart-home control, plus a calendar and weather display on a dedicated kiosk tablet. It integrates the phones, Sonos speakers, Spotify, Google Calendar and the kiosk tablet itself.

## Deployment

| Item | Detail |
|---|---|
| Host | [NUC](../hosts/nuc-docker-host.md), Docker Compose |
| Flavor | Home Assistant **Container**, not a HAOS VM |
| Image | Pinned to an exact release |
| Networking | `network_mode: host`, for device discovery |
| Config | Bind-mounted from the service-data drive, with the SELinux label applied |

## Decisions

- **Container instead of a HAOS VM on Proxmox:** Chosen with future Zigbee hardware in mind, and it keeps HA on the always-on Docker host next to the other services.
- **Bluetooth integration removed instead of granting privileges.** HA detected the NUC's built-in adapter over host networking and logged errors every 10 seconds. The container is host-networked on the tailnet's exit node, so I deleted the integration rather than grant it extra network capabilities. If Bluetooth is ever needed, the correct fix is bind-mounting `/run/dbus` read-only.
- **The tablet uses a non-admin user.** The wall display signs in as a dedicated account with the sidebar hidden, so a lost or tampered tablet can't change configuration.

## Backups

- **Two separate pieces:** Home Assistant writes its own consistent backups weekly (keeping 3), and a separate host script ships them to their own B2 bucket nightly, with its own scoped key.
- **Why separate:** A separate job and timer keeps failures and alerts distinguishable from the other backups.
- **Freshness check:** The script refuses to upload if the newest backup is more than 10 days old. That catches HA's scheduler failing silently while old files keep "succeeding."
- **History excluded on purpose:** The recorder database isn't in the backups. A restore brings back configuration and integrations, with empty graphs.

## Wall display

- **Dashboard:** A sections layout with a monthly calendar (Google Calendar integration), a clock and a weather forecast.
- **Kiosk app:** Fully Kiosk on the tablet, with motion-to-wake from the front camera, a screen-off timer, launch on boot and remote admin.
- **Clean display:** The HA header and sidebar are hidden with the `kiosk-mode` frontend plugin, installed through HACS.

## Gotchas

- **OAuth through My Home Assistant:** The redirect service stores the instance URL in the browser's local storage. Do the whole OAuth flow in one browser that's already configured, or the authorization code expires on a detour.
- **Google OAuth app status:** Must be published "In production." In Testing status, the Google Calendar sign-in returns `403 access_denied`.
- **Fully Kiosk's REST API sleeps with the screen,** so the HA integration shows "unavailable" whenever the tablet sleeps. That's expected, not a fault.
- **Fully's URL allowlist matches the whole URL, including the scheme.** `host*` blocks everything except the start page; use `http://host:8123*`.
- **New frontend plugins:** They need an HA restart **and** a hard browser refresh before they load.
- **Spotify can't target Sonos.** Spotify's API doesn't support Sonos as a playback device, so that route goes through Music Assistant instead.
