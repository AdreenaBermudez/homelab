# Service: Homepage dashboard

## What it does

A single landing page for the lab, built on [gethomepage](https://gethomepage.dev). It has live widgets for Jellyfin, both Pi-holes, Home Assistant and more, plus disk usage for every drive in the header.

## Deployment

| Item | Detail |
|---|---|
| Host | [NUC](../hosts/nuc-docker-host.md), in the monitoring Compose stack with Beszel and Portainer |
| Image | Pinned to an exact release |
| Docker socket | Mounted **read-only**, for container discovery |
| Access control | The tailnet; Homepage's built-in auth isn't enabled |

## Keeping secrets out of the config

The YAML config files are meant to be safe to publish, so they contain no secrets:

- **Where secrets live:** API keys and passwords are in `homepage.env` (mode 600). It's deliberately **not** named `.env`, so Compose doesn't also load it for its own variable interpolation.
- **How the config refers to them:** Placeholders like `{{HOMEPAGE_VAR_JELLYFIN_KEY}}`.
- **Result:** The committed config is safe by construction, instead of depending on remembering to scrub it.

## Disk usage in the header

- **Bind-mount what you want to measure:** Homepage reads disk stats from **inside its container**, so each drive it reports on is bind-mounted in read-only.
- **One block per drive:** Separate labeled `resources` blocks give each drive its own name, and `expanded: true` shows free and total space.
- **Failure mode:** If a drive drops out, its mountpoint becomes an empty directory on the OS disk, and the header silently shows the OS disk's numbers. The dashboard won't catch it; the storage canary alert does.

## Gotchas

- **Compose interpolates `$` in `env_file` values.** A password containing `$` arrived mangled in the container, so `curl` from the host worked while the widget got `401`.
  - **Diagnose:** Compare `md5sum` of the value on the host with the value inside the container.
  - **Fix:** Single-quote the value. Better, keep widget credentials plain alphanumeric: even with matching hashes, a `$` later broke the Pi-hole widget inside Homepage's own handler.
- **Env files are read at container creation.** Use `docker compose up -d --force-recreate`, not a restart.
- **New files in `/app/public`:** Next.js indexes that directory at startup, so a newly added background image returns 404 until the container is recreated.
- **Widget errors:** They go to `logs/homepage.log` in the config directory, not to `docker logs`. Some widget types don't log failures at all, so a silent log doesn't prove a widget works.
- **Pi-hole v6 widget:** Needs `version: 6` and a URL **without** `/admin`. The web admin password works as the key.
- **Background settings:** `cardBlur` and background brightness/opacity can't be used together. Setting both silently disables the blur.
