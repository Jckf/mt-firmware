#!/bin/sh
# Replace the packaged meshtasticd binary with a custom build from Jckf/mt-firmware and keep it updated.
#
# Usage (as root):
#   meshtasticd-custom.sh install [suffix]   divert the packaged binary, install the build, enable daily updates
#   meshtasticd-custom.sh update             fetch <suffix>-latest and install it if it changed (run by the timer)
#   meshtasticd-custom.sh status             show what is installed
#   meshtasticd-custom.sh uninstall          go back to the packaged binary
#
# The packaged binary is moved to /usr/bin/meshtasticd.distrib with dpkg-divert, so upgrades of the
# meshtasticd package keep updating it there and never overwrite the custom one.
set -eu

REPO=Jckf/mt-firmware
BIN=/usr/bin/meshtasticd
DISTRIB=/usr/bin/meshtasticd.distrib
SELF=/usr/local/sbin/meshtasticd-custom
CONF=/etc/default/meshtasticd-custom
UNIT=meshtasticd-custom-update
SERVICE=meshtasticd.service

die() {
	echo "meshtasticd-custom: $*" >&2
	exit 1
}

need_root() {
	[ "$(id -u)" = 0 ] || die "run as root"
}

arch() {
	case "$(dpkg --print-architecture)" in
	amd64) echo amd64 ;;
	arm64) echo arm64 ;;
	armhf) echo armv7 ;;
	*) die "no build for architecture $(dpkg --print-architecture)" ;;
	esac
}

diverted() {
	dpkg-divert --list "$BIN" | grep -q "$DISTRIB"
}

restart_daemon() {
	# Restarts the plain service and any running instances (meshtasticd@<name>).
	systemctl try-restart "$SERVICE" 'meshtasticd@*.service' 2>/dev/null || true
}

cmd_update() {
	need_root
	[ -r "$CONF" ] || die "not installed, run: $0 install"
	. "$CONF"
	diverted || die "$BIN is not diverted, run: $0 install"

	url="https://github.com/$REPO/releases/download/$SUFFIX-latest/meshtasticd-$(arch)-$SUFFIX"
	tmp=$(mktemp)
	trap 'rm -f "$tmp"' EXIT
	curl -fsSL --retry 3 -o "$tmp" "$url" || die "download failed: $url"
	chmod 755 "$tmp"

	if [ -x "$BIN" ] && cmp -s "$tmp" "$BIN"; then
		echo "up to date: $("$BIN" --version 2>/dev/null)"
		return 0
	fi

	# Running it proves the libraries it links against are present (a build for another Debian
	# release would fail here) and gives us the version to report.
	if ! version=$("$tmp" --version 2>&1); then
		echo "$version" >&2
		die "downloaded build does not run on this system, keeping the current binary"
	fi

	install -m 755 "$tmp" "$BIN.new"
	mv -f "$BIN.new" "$BIN"
	restart_daemon
	echo "installed $version"
}

cmd_install() {
	need_root
	suffix=${1:-jmd}
	command -v dpkg-divert >/dev/null || die "needs a Debian-based system"
	dpkg -s meshtasticd >/dev/null 2>&1 || die "install the meshtasticd package first"
	command -v curl >/dev/null || die "needs curl"
	arch >/dev/null

	if ! diverted; then
		dpkg-divert --local --rename --divert "$DISTRIB" --add "$BIN"
		# Keep the stock binary in place until the custom one has been verified.
		cp -p "$DISTRIB" "$BIN"
	fi

	echo "SUFFIX=$suffix" >"$CONF"

	# Install a copy of this script for the timer, unless we are already running from it.
	if [ "$(readlink -f "$0")" != "$SELF" ]; then
		[ -f "$0" ] || die "run this script from a file, not a pipe"
		install -m 755 "$0" "$SELF"
	fi

	cat >"/etc/systemd/system/$UNIT.service" <<EOF
[Unit]
Description=Update meshtasticd to the latest custom build
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$SELF update
EOF
	# Nightly CI starts at 03:00 UTC; the armv7 build takes a few hours.
	cat >"/etc/systemd/system/$UNIT.timer" <<EOF
[Unit]
Description=Daily meshtasticd custom build update

[Timer]
OnCalendar=*-*-* 09:00 UTC
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
	systemctl daemon-reload
	systemctl enable --now "$UNIT.timer"

	"$SELF" update
}

cmd_uninstall() {
	need_root
	systemctl disable --now "$UNIT.timer" 2>/dev/null || true
	rm -f "/etc/systemd/system/$UNIT.service" "/etc/systemd/system/$UNIT.timer"
	systemctl daemon-reload
	if diverted; then
		rm -f "$BIN"
		dpkg-divert --rename --remove "$BIN"
	fi
	rm -f "$CONF" "$SELF"
	restart_daemon
	echo "back on the packaged meshtasticd: $("$BIN" --version 2>/dev/null || echo unknown)"
}

cmd_status() {
	if [ -r "$CONF" ]; then
		. "$CONF"
		echo "build:     $SUFFIX ($REPO, $SUFFIX-latest)"
	else
		echo "build:     not installed"
	fi
	if diverted; then
		echo "installed: $("$BIN" --version 2>/dev/null || echo missing)"
		echo "packaged:  $("$DISTRIB" --version 2>/dev/null || echo missing) ($DISTRIB)"
	else
		echo "installed: $("$BIN" --version 2>/dev/null || echo missing) (packaged, not diverted)"
	fi
	systemctl list-timers "$UNIT.timer" --no-pager 2>/dev/null | sed -n 2p | sed 's/^/next run:  /'
}

case "${1:-}" in
install) shift; cmd_install "$@" ;;
update) cmd_update ;;
status) cmd_status ;;
uninstall) cmd_uninstall ;;
*) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
