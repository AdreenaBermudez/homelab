# Incident: Docker failed to start after an OS image update

**Date:** July 28, 2026
**Impact:** Every container on the NUC was down after the update and reboot
**Status:** Resolved

---

## Summary

The NUC runs Docker on Bazzite, an immutable Fedora Atomic image that updates as a whole with `rpm-ostree`. An image update removed the `runc` container runtime. Fedora's Docker engine still defaults to `runc`, so `docker.service` could not start any container.

## Symptoms

- **Service failure:** `docker.service` failed immediately after the reboot into the new image.
- **The error:** The journal showed `exec: "runc": executable file not found in $PATH`.

## Investigation

1. **Read the unit's journal** instead of retrying the service. The error was explicit about which binary was missing.
2. **Checked what changed.** The only change was the OS image update, which moved several versions forward in one step.
3. **Found why the binary disappeared.** The new image ships `crun` as the runtime for Podman and no longer includes `runc`. Nothing I had layered on the system provided it either.

## Root cause

On an immutable OS, the base image decides which packages exist. A dependency that Docker relied on was dropped from the base image, and because I had never layered it explicitly, it vanished with the update.

## Fix

- **Layered the runtime back:** `rpm-ostree install runc`, then rebooted into the new deployment.
- **Verified:** `docker.service` started, and every container came back up with its restart policy.

## Follow-up

- **Documented as required:** `runc` is recorded in my notes as a layered package that must stay installed, or Docker breaks the same way on a future update.
- **Monthly check updated:** The post-reboot checklist now looks for this exact journal signature.

## Lessons

- **On an immutable OS, list your implicit dependencies.** Anything a service needs that you didn't layer yourself can disappear in an image update.
- **Read the journal before restarting.** The first error line usually names the problem outright.
