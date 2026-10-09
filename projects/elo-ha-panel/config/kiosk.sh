#!/bin/bash
# /home/kiosk/kiosk.sh — runs at login for the local "kiosk" user (GNOME autostart).
# Applies session settings every login, starts an idle watcher, and keeps Brave in kiosk mode.

# --- Session settings (re-applied every login) ---
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.notifications show-banners false
gsettings set org.gnome.desktop.interface color-scheme prefer-dark
gsettings set org.gnome.desktop.session idle-delay 30
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type nothing
gsettings set org.gnome.settings-daemon.peripherals.touchscreen orientation-lock true

BRAVE=$(command -v brave-browser || command -v brave)
URL="http://192.168.4.20:8123/elo-panel"   # Home Assistant dashboard

# --- Auto-return: after 60 s with no input, restart Brave once (back to one clean tab) ---
(
  reset_done=0
  while sleep 10; do
    idle=$(gdbus call --session --dest org.gnome.Mutter.IdleMonitor \
      --object-path /org/gnome/Mutter/IdleMonitor/Core \
      --method org.gnome.Mutter.IdleMonitor.GetIdletime | grep -o '[0-9]\+' | tail -1)
    if [ "${idle:-0}" -gt 60000 ]; then
      [ "$reset_done" -eq 0 ] && pkill -u kiosk -x brave && reset_done=1
    else
      reset_done=0
    fi
  done
) &

# --- Brave kiosk loop: relaunches 3 s after any exit, with no restored tabs ---
while true; do
  rm -rf /home/kiosk/.config/BraveSoftware/Brave-Browser/Default/Sessions
  "$BRAVE" --kiosk --force-dark-mode --password-store=basic --no-first-run --noerrdialogs \
    --hide-crash-restore-bubble --ozone-platform-hint=auto "$URL"
  sleep 3
done
