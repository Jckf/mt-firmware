# Installing a custom meshtasticd

The meshtasticd builds here (currently [`jckf/mqtt-duplicates`](../README.md#jckfmqtt-duplicates), suffix `jmd`) are bare binaries meant to replace `/usr/bin/meshtasticd` from the official `meshtasticd` package. [`scripts/meshtasticd-custom.sh`](../scripts/meshtasticd-custom.sh) does that and keeps the binary updated.

## Requirements

- Debian or Raspberry Pi OS **trixie**, on amd64, arm64 or 32-bit armv7. The binaries link against trixie's libraries, so they do not run on bookworm. The script checks this before installing anything, and keeps the stock binary if the build does not run.
- The official `meshtasticd` package installed and configured ([Meshtastic Linux install docs](https://meshtastic.org/docs/software/linux/installation/)). Configuration, the web UI and the systemd service all come from the package.
- `curl`.

Not supported: Pi Zero and Pi 1 (armv6) and anything that is not Debian-based.

## Install

```sh
curl -fsSLO https://raw.githubusercontent.com/Jckf/mt-firmware/refs/heads/jckf/main/scripts/meshtasticd-custom.sh
sudo sh meshtasticd-custom.sh install jmd
```

What it does:

1. Diverts the packaged binary to `/usr/bin/meshtasticd.distrib` with `dpkg-divert`. Package upgrades update it there and never overwrite the custom one.
2. Copies itself to `/usr/local/sbin/meshtasticd-custom` and writes the chosen suffix to `/etc/default/meshtasticd-custom`.
3. Enables `meshtasticd-custom-update.timer`, which runs daily at about 09:00 UTC (after the nightly build).
4. Downloads `<suffix>-latest` for this machine's architecture, checks that it runs (`meshtasticd --version`), installs it and restarts meshtasticd.

Each update downloads the latest build and only installs and restarts when it differs from the installed binary. A build that does not run on the system is never installed.

## Day to day

```sh
sudo meshtasticd-custom status      # installed and packaged versions, next update
sudo meshtasticd-custom update      # update now
journalctl -u meshtasticd-custom-update   # update log
```

To update weekly instead of daily:

```sh
sudo systemctl edit meshtasticd-custom-update.timer
```

```ini
[Timer]
OnCalendar=
OnCalendar=Mon 09:00 UTC
```

To stop updates but keep the current binary: `sudo systemctl disable --now meshtasticd-custom-update.timer`.

## Uninstall

```sh
sudo meshtasticd-custom uninstall
```

Removes the timer, the custom binary and the diversion, puts the packaged binary back and restarts meshtasticd.

## Things to know

- The builds are upstream `develop` plus the patch, rebuilt nightly. They are usually ahead of the packaged release, while config templates and the web UI stay at the package's version.
- The firmware reports the upstream version with the patch commit, e.g. `2.8.3.8edc62f`, and `firmware_edition` `DIY_EDITION`.
- These builds are not supported by the Meshtastic project; do not report problems with them upstream.
