# Incident: New logins failing while existing sessions worked

**Date:** August 25, 2026
**Impact:** Nobody could sign in to Jellyfin on a new or reset client; already signed-in clients kept working
**Status:** Resolved

---

## Summary

Jellyfin rejected every fresh login with a generic "Connection Failure," while clients with existing sessions streamed normally. The pattern pointed away from the server, but the container logs showed a database concurrency exception inside the login flow. It matched a known upstream bug in the default database locking mode introduced in Jellyfin 10.11.

## Symptoms

- **Login failure:** The web client loaded the login page, then showed "Connection Failure — unable to connect to the selected server" after credentials were entered.
- **Partial function:** Static pages loaded and existing sessions worked, which made it look like a client or network problem.

## Investigation

1. **Confirmed the server was reachable.** The public system-info endpoint returned 200 in under a millisecond. Disk space was fine.
2. **Watched the logs during a login attempt.** `docker logs -f` showed a .NET exception stack running through `UserManager.AuthenticateUser` and `SessionManager.AuthenticateNewSessionInternal`.
3. **Found the actual exception.** It was a `DbUpdateConcurrencyException` ("expected 1 row, affected 0") thrown by the database layer's `NoLock` locking behavior.
4. **Matched it upstream.** It lined up exactly with [jellyfin/jellyfin#16353](https://github.com/jellyfin/jellyfin/issues/16353). Authentication succeeds; the crash happens afterward, when retiring the old session token and creating the new one both update the same user row and race on its optimistic-concurrency version column. Once it starts, it reinforces itself.

## Root cause

A known upstream bug in the default `NoLock` database locking mode. Each failed attempt pushed the user row's version counter further out of step. By the time I fixed it, the counter had reached 2,494.

## Fix

1. **Backed up first:** Copied both the database configuration file and the SQLite database.
2. **Stopped cleanly:** `docker stop jellyfin`, so SQLite checkpointed its write-ahead log.
3. **Changed the locking mode** in the database configuration from `NoLock` to `Pessimistic`.
4. **Reset the corrupted state:** Reset the user row's version counter and cleared the device-session table.
5. **Started and verified:** Password sign-in succeeded, and libraries and watch history were intact.

**Side effect:** Every client had to sign in once more, because stale device sessions were cleared.

## Lessons

- **"Existing sessions work, new logins fail" is a server-side signature.** It hides behind a client-looking error message.
- **Get the exception type, not just the stack trace.** The type and message are what make an upstream search precise.
- **Know where a container really keeps its data.** Here the Docker bind mount was Jellyfin's data root, and the config file sat one directory deeper than expected.
