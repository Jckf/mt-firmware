# Custom Meshtastic builds

Small patch sets on top of [meshtastic/firmware](https://github.com/meshtastic/firmware), rebased onto upstream `develop` and rebuilt automatically every night.

Not supported by the Meshtastic project. Report problems here, not upstream.

## Builds

| Branch | Version suffix | Change | Boards |
| --- | --- | --- | --- |
| [`jckf/powerlimit`](../../tree/jckf/powerlimit) | `-jpl` | `EU_868`, `EU_866` and `EU_N_868` power limit raised from 27 to 30 dBm | T-Beam 1W, RAK3401 + RAK13302, WisMesh Repeater Mini HP, Heltec V4, V4 R8, Mesh Node T096, Wireless Tracker V2, Mesh Tower V2, Meshnology W12 |
| [`jckf/mqtt-duplicates`](../../tree/jckf/mqtt-duplicates) | `-jmd` | MQTT uplink of every heard copy of a packet, not just the first | meshtasticd (Linux amd64, arm64, armv7), T-Beam 1W, Heltec V4, V4 R8, Wireless Tracker V2, Meshnology W12 |

### `jckf/powerlimit`

EU short-range-device limits are specified as ERP (27 dBm). The firmware applies the region limit at the radio's output, so the stock 27 dBm leaves the 2.15 dB between ERP and EIRP, and any cable and connector loss, unused. This build raises the limit to 30 dBm. Only boards with an external power amplifier can make use of it:

| Board | Max output |
| --- | --- |
| LilyGo T-Beam 1W | 30 dBm |
| RAK3401 + RAK13302 / WisMesh Repeater Mini HP | about 29 dBm |
| Heltec V4, V4 R8, Mesh Node T096, Wireless Tracker V2, Mesh Tower V2; Meshnology W12 | about 28 dBm |

**The operator is responsible for staying within the limits that apply to their installation.** Set a lower `tx_power` if your antenna gain exceeds your feedline loss plus 2.15 dB.

### `jckf/mqtt-duplicates`

A port of [meshtastic/firmware#10531](https://github.com/meshtastic/firmware/pull/10531) onto current `develop`, with `USERPREFS_MQTT_UPLINK_ALL_SEEN` turned on. Stock firmware uplinks a packet to MQTT only the first time it is heard; this build also uplinks every later copy (rebroadcasts by other relays, including of our own packets), so MQTT analytics see the SNR of every relay heard and traceroute paths that only arrive on a later copy. With MQTT encryption enabled, encrypted DMs between other nodes are uplinked once per heard copy as well.

Only useful on a node with MQTT uplink enabled, and it multiplies the MQTT traffic. Built for the ESP32-S3 boards listed above, which uplink over WiFi and flash like any other release, and as `meshtasticd`. The meshtasticd binary is the `native-tft` environment (like the Debian packages) built against Debian trixie, so it replaces `/usr/bin/meshtasticd` from the meshtasticd package on Debian or Raspberry Pi OS trixie. To install it and keep it updated:

```sh
curl -fsSLO https://raw.githubusercontent.com/Jckf/mt-firmware/refs/heads/jckf/main/scripts/meshtasticd-custom.sh
sudo sh meshtasticd-custom.sh install jmd
```

See [Installing a custom meshtasticd](docs/meshtasticd.md) for what that does, updates and uninstalling.

## Downloads

Each patch set has a release that every new build replaces. The links below never change:

| Branch | Release |
| --- | --- |
| `jckf/powerlimit` | [jpl-latest](../../releases/tag/jpl-latest) |
| `jckf/mqtt-duplicates` | [jmd-latest](../../releases/tag/jmd-latest) |

Direct links per board follow the pattern `https://github.com/Jckf/mt-firmware/releases/download/<suffix>-latest/firmware-<pio_env>-<suffix>.zip`, e.g. [firmware-t-beam-1w-jpl.zip](https://github.com/Jckf/mt-firmware/releases/download/jpl-latest/firmware-t-beam-1w-jpl.zip). Flash it like any other Meshtastic release. meshtasticd builds are the bare binary: `https://github.com/Jckf/mt-firmware/releases/download/<suffix>-latest/meshtasticd-<arch>-<suffix>`. The firmware reports the upstream version with the patch branch's commit hash, e.g. `2.8.3.949efa6`, and `firmware_edition` `DIY_EDITION`.

## Branches

| Branch | Contents |
| --- | --- |
| `jckf/main` | This README, `builds.json`, the CI and the meshtasticd install script (default branch) |
| `develop` | Upstream's branch as of the fork, not maintained. Pushing to it starts upstream's full CI in this fork |
| `jckf/<name>` | One patch set each, rebased onto upstream `develop` nightly |

## Adding a build

1. Create `jckf/<name>` from upstream `develop` and commit the patches:
   ```sh
   git remote add upstream https://github.com/meshtastic/firmware.git   # once
   git fetch upstream develop && git switch -c jckf/<name> upstream/develop
   ```
2. Add an entry to `builds.json`: branch, version suffix, description and `{platform, pio_env}` targets. For meshtasticd use `{"platform": "portduino", "pio_env": "native-tft", "arch": "amd64" | "arm64" | "armv7"}`; armv7 builds under QEMU and takes a few hours.
3. Push `builds.json`. That triggers a full build and creates the `<suffix>-latest` release; after that the branch is rebased and rebuilt whenever upstream moves.

After pushing new commits to a patch branch, run [Sync and build](../../actions/workflows/sync-and-build.yml) by hand with that branch and *Build even if upstream has not moved* ticked. The nightly run only builds branches that upstream moved.

If a patch set stops rebasing cleanly, the run fails (and opens an issue if issues are enabled). Rebase the branch by hand and push it.
