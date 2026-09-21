# Runbook: UPS "Lost Communication"

The CyberPower UPS connects to the Proxmox host over USB and is monitored by CyberPower's `pwrstatd` daemon. When `pwrstat -status` reports **State: Lost Communication**, the host can no longer see the UPS and would not get a warning before the battery runs out.

---

## Quick fix

1. **Check what holds the USB device:**
   ```bash
   fuser /dev/bus/usb/<bus>/<device>
   ```
2. **If something other than `pwrstatd` holds it,** stop that service. In practice this has always been NUT (see below).
3. **If nothing holds it,** the USB endpoint is wedged. Unbind and rebind the UPS's USB path in sysfs instead of physically replugging it:
   ```bash
   echo '<ups-usb-path>' > /sys/bus/usb/drivers/usb/unbind
   sleep 3
   echo '<ups-usb-path>' > /sys/bus/usb/drivers/usb/bind
   /etc/init.d/pwrstatd start
   ```
4. **Confirm the fix:** `pwrstat -status` should show `State: Normal`.

---

## Find the right USB path first

**⚠️ Always confirm the path before unbinding.** On this host, the neighboring USB path is a hub carrying two storage drives, including one that holds media and an NFS backup export. Unbinding the wrong path once re-enumerated both drives mid-operation. They survived, but it was avoidable.

Find the UPS by its CyberPower vendor ID (`0764`):

```bash
for d in /sys/bus/usb/devices/*/; do
  [ -f "$d/idVendor" ] && grep -q 0764 "$d/idVendor" && echo "$d"
done
```

---

## Why NUT must be masked, not just disabled

NUT (Network UPS Tools) and `pwrstatd` both try to own the same USB device and constantly break each other's connection. I chose `pwrstatd` as the only monitor and disabled NUT.

- **What went wrong:** NUT came back on its own after a package update. Its `nut-driver-enumerator` regenerates and re-enables the driver unit, so **disabling isn't enough.**
- **What the conflict looks like:** Repeated `usbhid-ups: ... Input/Output Error` lines and `Data for UPS is stale` from `upsd`.
- **The fix:** Mask everything, including **both** enumerator units. Masking the service alone isn't enough, because the `.path` unit still triggers it.

```bash
systemctl mask --now nut-monitor nut-server nut-driver@<ups-name> \
  nut-driver-enumerator.service nut-driver-enumerator.path
```

Verify with `systemctl list-unit-files | grep nut`. Every NUT unit should show `masked`.

---

## Gotchas

- **Restarting `pwrstatd`:** `systemctl restart pwrstatd` can silently fail to start it. `/etc/init.d/pwrstatd start` works reliably.
- **Don't trust a 0 W load reading after a reconnect.** After one USB reconnect, both the daemon and the UPS's own display showed 0 W load. A real mains-pull test proved everything was on battery-backed outlets (it read 44 W with about 88 minutes of runtime). The sensor simply hadn't resumed reporting until a real power event shook it loose.
- **The communication problem predated the NUT conflict.** The daemon log showed communication breaking the day *before* NUT returned. If the fix above doesn't hold, suspect the cable or the UPS's USB port too.
