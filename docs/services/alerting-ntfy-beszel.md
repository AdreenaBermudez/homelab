# Alerting — ntfy + Beszel

Casa Bermudez notification stack. Built 2026-07-31.

Before this existed, monitoring was dashboards only: Beszel showed problems accurately but silently, so an outage was found by looking rather than by being told. Two failures in July (the Jul 27 tailnet DNS outage, the Jul 28 Docker/runc breakage) went unnoticed until manual investigation.

## Architecture

```
Beszel hub ──┐
             ├──> ntfy (NUC :8888) ──> iPhone (ntfy app)
systemd    ──┘         │
OnFailure              └──> poll request via ntfy.sh ──> APNs
```

- **ntfy** — self-hosted notification server on the NUC, the single endpoint everything publishes to
- **Beszel** — publishes host up/down and resource threshold alerts
- **systemd `OnFailure=`** — publishes backup job failures, which Beszel structurally cannot see (host healthy, job dead)

## ntfy

**Location:** `~/ntfy/docker-compose.yml` on the NUC (192.168.4.20)
**Image:** `binwiederhier/ntfy:v2.11.0` (pinned)
**Port:** 8888 → 80
**Data:** `/var/mnt/data/ntfy/{cache,etc}`

Bazzite requires SELinux labelling on any bind-mounted directory:

```bash
sudo chcon -Rt svirt_sandbox_file_t /var/mnt/data/ntfy
```

### docker-compose.yml

```yaml
services:
  ntfy:
    image: binwiederhier/ntfy:v2.11.0
    container_name: ntfy
    command: serve
    restart: unless-stopped
    ports:
      - "8888:80"
    volumes:
      - /var/mnt/data/ntfy/cache:/var/cache/ntfy
      - /var/mnt/data/ntfy/etc:/etc/ntfy
      - /var/mnt/data/ntfy/etc:/var/lib/ntfy
    healthcheck:
      test: ["CMD-SHELL", "wget -q --tries=1 -O - http://localhost:80/v1/health | grep -Eo '\"healthy\"\\s*:\\s*true' || exit 1"]
      interval: 60s
      timeout: 10s
      retries: 3
```

### server.yml

`/var/mnt/data/ntfy/etc/server.yml`:

```yaml
base-url: "https://nuc-computer.tailff4a79.ts.net:8443"
listen-http: ":80"
cache-file: "/var/cache/ntfy/cache.db"
cache-duration: "72h"
auth-file: "/var/lib/ntfy/user.db"
auth-default-access: "deny-all"
behind-proxy: true
upstream-base-url: "https://ntfy.sh"
```

### TLS via Tailscale

Vaultwarden already owned 443 root on this node, so ntfy uses port 8443 rather than path-based routing (which the iOS app handles poorly):

```bash
sudo tailscale serve --bg --https 8443 http://127.0.0.1:8888
```

Verify with `sudo tailscale serve status` — expect 443 → 8222 (Vaultwarden) and 8443 → 8888 (ntfy). Both tailnet-only, Funnel disabled.

### Auth

`auth-default-access: deny-all` — anonymous users have no access to any topic.

User `adreena` (role admin). **Password and access token are in Vaultwarden** under "Casa Bermudez — ntfy". Not recorded here.

```bash
docker exec -it ntfy ntfy user list          # verify permissions
docker exec -it ntfy ntfy token add adreena  # create a token
```

Primary topic: `casa-alerts`

### iOS instant delivery

iOS restricts background processing, so a self-hosted ntfy server cannot push directly — without extra config, notifications only appear when the app is opened, and can otherwise take hours.

`upstream-base-url: "https://ntfy.sh"` fixes this. Incoming messages trigger a *poll request* to ntfy.sh carrying only the message ID; ntfy.sh relays it via APNs; the phone then fetches the actual content from the NUC. **Message content never leaves the local network.**

Requirements:

- `base-url` must exactly match the server URL entered in the iOS app, `:8443` included
- Tailscale must be connected on the phone, or notifications arrive as a contentless "New message" placeholder
- Subscriptions created before this setting was added do not inherit it — unsubscribe and re-add the topic

There is no Beszel mobile app. ntfy is the notification client for everything.

## Beszel

**Notification URL** (Settings → Notifications), Shoutrrr format:

```
ntfy://adreena:<PASSWORD>@192.168.4.20:8888/casa-alerts?scheme=http
```

Password in Vaultwarden. Uses the LAN address so alert traffic stays local instead of routing out through Tailscale and back.

### APP_URL — required

The "View Beszel" deep link in notifications comes from the `APP_URL` environment variable, **not** any web-UI setting. It defaults to `http://localhost:8090`, which on a phone means the phone itself — the link fails.

In `~/monitoring/docker-compose.yml`:

```yaml
  beszel:
    environment:
      - APP_URL=http://192.168.4.20:8090
```

A plain `docker compose up -d` reports "Started" without applying it. Use:

```bash
docker compose up -d --force-recreate beszel
```

Verify with `docker inspect beszel --format '{{json .Config.Env}}'`. Note: `docker exec beszel env` returns nothing on this image — it has no `env` binary. That silence is not a failure.

### Alerts configured

| System | Alerts |
|---|---|
| nuc-nextcloud | Status (down), Disk 85% |
| Casa-bermudez (Proxmox) | Status (down) |
| pi1-pihole | Status (down) |
| pi2-pihole | Status (down), Memory 90% |

Status delay ~5 minutes so reboots and brief blips don't page.

**CPU alerts are deliberately not set.** The Proxmox host runs an elevated load average from Netdata's apps.plugin as its normal state. An alert that fires during healthy operation trains you to ignore your phone.

## Backup failure alerting

Covers the case Beszel misses: host up and healthy, backup job dead.

**`/etc/ntfy.env`** (chmod 600, root-only) — holds `NTFY_URL` and `NTFY_TOKEN`. Single place to edit on rotation. Token in Vaultwarden.

```
NTFY_URL=http://192.168.4.20:8888/casa-alerts
NTFY_TOKEN=<in Vaultwarden>
```

**`/usr/local/bin/ntfy-alert`** (chmod 700) — reusable sender:

```bash
#!/bin/bash
# Casa Bermudez — send an ntfy alert
# Usage: ntfy-alert "<title>" "<message>" [priority] [tags]
set -euo pipefail
source /etc/ntfy.env
curl -fsS \
  -H "Authorization: Bearer ${NTFY_TOKEN}" \
  -H "Title: ${1:-Casa Bermudez}" \
  -H "Priority: ${3:-high}" \
  -H "Tags: ${4:-rotating_light}" \
  -d "${2:-(no message)}" \
  "${NTFY_URL}" > /dev/null
```

**`/etc/systemd/system/ntfy-failure@.service`** — oneshot template calling `ntfy-alert` for failed unit `%i`:

```ini
[Unit]
Description=ntfy alert on failure of %i

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ntfy-alert "Casa Bermudez — %i FAILED" "Unit %i failed on nuc-nextcloud. Check: journalctl -u %i -n 50"
```

**Wiring** via drop-ins rather than unit edits, so they survive a rewrite of the originals:

```
/etc/systemd/system/nextcloud-backup.service.d/ntfy.conf
/etc/systemd/system/anytype-backup.service.d/ntfy.conf
```

Each containing:

```ini
[Unit]
OnFailure=ntfy-failure@%n.service
```

Verify:

```bash
systemctl show nextcloud-backup.service -p OnFailure
systemctl show anytype-backup.service -p OnFailure
```

The doubled `.service` in the output is correct — `%n` expands to the full unit name, which becomes the instance.

**Known gap:** a backup script that exits 0 but silently uploads nothing is still undetected. Needs an in-script check, not yet built.

## Verification

Smoke test (immediate):

```bash
sudo /usr/local/bin/ntfy-alert "Casa Bermudez" "test"
```

systemd failure chain:

```bash
sudo systemd-run --unit=ntfy-test-fail --property=OnFailure=ntfy-failure@ntfy-test-fail.service /bin/false
sudo systemctl reset-failed ntfy-test-fail.service
```

Full end-to-end (monthly, tracked in Todoist):

```bash
ssh adreenabermudez87@192.168.4.216 "sudo systemctl stop beszel-agent"
# wait 7-8 min, confirm down push
ssh adreenabermudez87@192.168.4.216 "sudo systemctl start beszel-agent"
# confirm recovery push
ssh adreenabermudez87@192.168.4.216 "systemctl is-active beszel-agent tailscaled"
```

Stopping and immediately restarting fires nothing — the outage must outlast the 5-minute delay. This caused a false "it didn't work" during initial testing.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Nothing arrives, ever | Check `docker logs beszel --tail 50` for Shoutrrr errors |
| Notification says "New message", no content | Phone can't reach the NUC — Tailscale disconnected |
| Notifications only appear when app is opened | `upstream-base-url` missing, or subscription predates it |
| 403 on publish | Expected without a token — `deny-all` working |
| 401 on publish | Wrong or placeholder token |
| "View Beszel" link fails | `APP_URL` not applied — force-recreate the container |

## Maintenance

Tracked in Todoist, project **Maintenance Schedules**:

- **Monthly** — verify alerting still fires end-to-end. Silent alerting failure makes the whole stack worthless and nothing else would reveal it.
- **Quarterly** — rotate the ntfy token and B2 application keys.
- **Monthly (NUC reboot task)** — includes ntfy in the container list, a `tailscale serve status` check, and an `ntfy-alert` smoke test.

## Secrets

Not in this repo, by design: ntfy user password, ntfy access token, Beszel notification URL (embeds the password). All in Vaultwarden.
