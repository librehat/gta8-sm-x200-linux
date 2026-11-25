#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Bring up the host side of the Nura Edge USB gadget network (RNDIS/NCM).
#
# usage:
#   usbnet-up.sh [-i IFACE] [-a HOST_CIDR] [-d DEVICE_IP] [-t TIMEOUT]
#
#   -i IFACE      host interface to configure (default: auto-detect)
#   -a CIDR       host address (default: 172.16.42.2/24)
#   -d IP         device address to ping afterwards (default: 172.16.42.1)
#   -t SECONDS    how long to wait for the interface to appear (default: 30)
#
# Then connect with:  ssh user@172.16.42.1
set -euo pipefail

IFACE=""
HOST_CIDR="172.16.42.2/24"
DEVICE_IP="172.16.42.1"
TIMEOUT=30

usage() {
	sed -n '3,14s/^# \{0,1\}//p' "$0"
	exit "${1:-0}"
}

log() { printf '>> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while getopts "i:a:d:t:h" opt; do
	case $opt in
	i) IFACE=$OPTARG ;;
	a) HOST_CIDR=$OPTARG ;;
	d) DEVICE_IP=$OPTARG ;;
	t) TIMEOUT=$OPTARG ;;
	h) usage 0 ;;
	*) usage 1 ;;
	esac
done

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

# Find a USB network interface backed by a gadget-class host driver.
detect_iface() {
	local dev drv
	for dev in /sys/class/net/*; do
		[ -e "$dev/device/driver" ] || continue
		drv=$(basename "$(readlink -f "$dev/device/driver")")
		case $drv in
		rndis_host|cdc_ncm|cdc_ether|cdc_eem|cdc_subset)
			basename "$dev"
			return 0
			;;
		esac
	done
	return 1
}

if [ -z "$IFACE" ]; then
	log "waiting up to ${TIMEOUT}s for the USB gadget interface..."
	for _ in $(seq "$TIMEOUT"); do
		IFACE=$(detect_iface) && break
		sleep 1
	done
	[ -n "$IFACE" ] || die "no USB gadget network interface found (check 'lsusb' and 'dmesg | tail')"
else
	[ -e "/sys/class/net/$IFACE" ] || die "interface '$IFACE' does not exist"
fi
log "using interface: $IFACE"

# Keep NetworkManager from fighting over the link (DHCP attempts etc.).
if command -v nmcli >/dev/null && nmcli -t general status >/dev/null 2>&1; then
	$SUDO nmcli device set "$IFACE" managed no || true
fi

$SUDO ip addr flush dev "$IFACE"
$SUDO ip addr add "$HOST_CIDR" dev "$IFACE"
$SUDO ip link set "$IFACE" up
ip -br addr show dev "$IFACE" >&2

if ping -c 3 -W 2 -I "$IFACE" "$DEVICE_IP" >/dev/null 2>&1; then
	log "device reachable at $DEVICE_IP — try: ssh user@$DEVICE_IP"
else
	log "WARNING: $DEVICE_IP not answering ping yet (device may still be booting)"
fi
