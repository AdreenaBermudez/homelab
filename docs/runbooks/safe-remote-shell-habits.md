# Runbook: Safe remote-shell habits

Most of my self-inflicted problems in this lab weren't configuration mistakes. They were commands that ran somewhere I didn't intend, or text that didn't arrive the way I pasted it. These are the rules I follow now, each earned by a specific failure.

---

## Know which host you're on

- **A failed `ssh` doesn't stop the rest of a pasted block.** If `ssh` fails ("No route to host") and later commands were in the same paste, those commands **run on the local machine.** The output looks valid; it's just from the wrong host.
  - **Rule:** Run `ssh` by itself, wait for the remote prompt, **read the hostname in it,** then paste.
- **A successful `ssh` can swallow the paste too.** Lines pasted during connection setup can be eaten by the login banner or buffered and lost.
- **`scp` runs where you type it.** An `scp` pasted into a block of server commands ran on the server and looked for the file in the server's `~/Downloads`. Run `scp` from a separate local terminal tab.

---

## Pasting and interactive prompts

- **Never paste a block that contains an interactive prompt** (`read`, `nano`, `ssh`, `passwd`). The shell buffers the following lines, and the prompt consumes them as its answer. This produced truncated secrets and an editor that opened and closed instantly.
  - **Rule:** Send the interactive command alone, answer it, then send the rest.
- **Hidden-input prompts and bracketed paste don't mix.** `read -rsp` (hidden) silently truncated pasted values where `read -rp` (visible) captured them correctly.
- **Watch for an open editor.** A heredoc typed while `nano` was still open went into the file instead of the shell, corrupted a YAML config and crash-looped a container.

---

## `sudo` pitfalls

- **Pasting right behind `sudo -i` gets eaten by the shell transition.** The root shell consumed the whole paste and printed the login banner instead of running anything.
  - **Rule:** Send `sudo -i` alone, wait for the `#` prompt, then paste.
- **A `sudo` password prompt can cancel a long command.** Ctrl-C at the prompt cancels the command, sometimes after it has partly run. A large `rm -rf` inside `tmux` stopped partway twice this way.
  - **Rule:** For long root operations, `sudo -i` first, then run the command with no prompt left to interrupt it.
- **Never background `sudo` with `&`.** It detaches from the terminal, so the password prompt can't hide input, and the typed password goes to the shell **as a command, in plain text.** (The password was rotated afterward.)
  - **Rule:** For a command that will cut off its own SSH session (such as restarting networking), run `sudo -i`, then `systemd-run --unit=<name> bash -c '...'`.

---

## Getting files onto a host intact

- **Long heredocs can be mangled by zsh.** Pasting a large heredoc into the Mac terminal silently dropped three code blocks from a Markdown file. The tell is `heredoc>` prompts mixed with completion noise.
  - **Rule:** For anything longer than a few lines, download the file and move it into place. Then sanity-check it, for example ``grep -c '```' file.md`` must print an even number.
- **`scp` doesn't preserve the execute bit** when copying a script onto a host. Run `chmod +x` after moving it.
- **Keep secrets out of heredocs and command lines.** Write them into a mode-600 env file with a script, then verify the value's **length** instead of printing it:
  ```bash
  awk '/VAR_NAME/{i=index($0,"=");print substr($0,1,i-1),"length:",length(substr($0,i+1))}' app.env
  ```

---

## Docker-specific

- **`docker compose up -d` can say "Started" without applying a change.** It happened three times in one day.
  - **Rule:** Use `--force-recreate` and verify with `docker inspect <c> --format '{{.Config.Image}}'`.
- **Compose interpolates `$` inside `env_file` values.** A password containing `$` arrived mangled inside the container.
  - **Diagnose:** Compare `md5sum` of the value on the host with `docker exec <c> sh -c 'printf %s "$VAR"' | md5sum`.
  - **Fix:** Wrap the value in single quotes. For credentials a container will pass on to another service, prefer plain alphanumeric passwords.
- **`pgrep -a rm` gives false positives** by matching kernel threads. Use `pgrep -x rm` to find a real `rm` process.

---

## The underlying habit

**Slow down at the boundaries:** host switches, privilege switches, and anything interactive. Nearly every entry on this page happened at one of those three places.
