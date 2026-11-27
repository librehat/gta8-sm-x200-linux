#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build and flash Nura Edge (postmarketOS) cleanly for Samsung Galaxy Tab A8
# (SM-X200/SM-X205) with UWE5622 wireless firmware and the local kernel tree.
#
# usage:
#   flash-gta8.sh build [-- <pmbootstrap install args...>]
#   flash-gta8.sh install [-- <pmbootstrap install args...>]
#   flash-gta8.sh build-kernel
#   flash-gta8.sh flash [--with-dtbo] [--no-reboot]
#   flash-gta8.sh flash-kernel [--with-dtbo] [--no-reboot]
#   flash-gta8.sh all [--with-dtbo] [--no-reboot] [-- <pmbootstrap install args...>]
#   flash-gta8.sh -h | --help
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
EXPORT_DIR="/tmp/postmarketOS-export"
FW_DIR="$ROOT/firmware/uwe5622"
TS_DIR="$ROOT/firmware/touchscreen"
FW_STAGE="$ROOT/firmware/.pkg-stage"
DTBO_IMG="$ROOT/firmware/dtbo-noop.img"
DEFAULT_PASSWORD="147147"

trap 'rm -rf "$FW_STAGE"' EXIT

WITH_DTBO=0
NO_REBOOT=0
INSTALL_ARGS=()

usage() {
	sed -n '3,15s/^# \{0,1\}//p' "$0"
	exit "${1:-0}"
}

log() { printf '>> %s\n' "$*" >&2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { for c; do command -v "$c" >/dev/null || die "missing tool: $c"; done; }

parse_flash_and_install_args() {
	while [ $# -gt 0 ]; do
		case $1 in
		--with-dtbo) WITH_DTBO=1 ;;
		--no-reboot) NO_REBOOT=1 ;;
		--)
			shift
			INSTALL_ARGS=("$@")
			return 0
			;;
		-h|--help) usage 0 ;;
		*) die "unknown option: $1 (pass install args after '--')" ;;
		esac
		shift
	done
}

cmd_build() {
	need pmbootstrap
	if [ ! -f "$FW_DIR/wcnmodem.bin" ]; then
		die "missing $FW_DIR/wcnmodem.bin; run $ROOT/tools/extract-firmware.sh --pull-wireless first"
	fi
	if [ ! -f "$FW_DIR/wifi_board_config.ini" ]; then
		warn "missing $FW_DIR/wifi_board_config.ini; Wi-Fi board config may fail unless staged"
	fi
	if [ ! -f "$TS_DIR/nt36523b_qc_inx_fw.bin" ]; then
		warn "missing $TS_DIR/nt36523b_qc_inx_fw.bin; touchscreen will lag or fail without firmware"
		warn "stage it via: $ROOT/tools/extract-firmware.sh --pull-touchscreen (or copy .bin to $TS_DIR/)"
	fi

	rm -rf "$FW_STAGE"
	mkdir -p "$FW_STAGE/uwe5622" "$FW_STAGE/touchscreen"
	cp -a "$FW_DIR/." "$FW_STAGE/uwe5622/"
	if compgen -G "$TS_DIR/*.bin" >/dev/null; then
		cp -a "$TS_DIR"/*.bin "$FW_STAGE/touchscreen/"
	fi

	log "building firmware-samsung-gta8 from $FW_STAGE"
	pmbootstrap build firmware-samsung-gta8 --src="$FW_STAGE" --force

	log "building device-samsung-gta8"
	pmbootstrap build device-samsung-gta8 --force

	log "building linux-samsung-gta8 from $ROOT/linux"
	pmbootstrap build linux-samsung-gta8 --src="$ROOT/linux" --force

	cmd_install
}

cmd_install() {
	need pmbootstrap

	# Reset chroot mounts and stale /dev/install* loop nodes before installing.
	log "cleaning up stale pmbootstrap chroots/loop devices"
	pmbootstrap shutdown

	local -a install_cmd=(pmbootstrap install)
	local has_pw=0 arg
	for arg in "${INSTALL_ARGS[@]}"; do
		case $arg in
		--password|--password=*) has_pw=1 ;;
		esac
	done
	if [ "$has_pw" = 0 ]; then
		install_cmd+=(--password "$DEFAULT_PASSWORD")
	fi
	install_cmd+=("${INSTALL_ARGS[@]}")

	log "building rootfs image (${install_cmd[*]})"
	"${install_cmd[@]}"

	log "exporting images to $EXPORT_DIR"
	pmbootstrap export

	ls -lhL "$EXPORT_DIR/samsung-gta8.img" "$EXPORT_DIR/boot.img"
}

cmd_build_kernel() {
	need pmbootstrap

	log "building linux-samsung-gta8 from $ROOT/linux"
	pmbootstrap build linux-samsung-gta8 --src="$ROOT/linux" --force

	log "upgrading linux-samsung-gta8 in device rootfs chroot"
	pmbootstrap chroot -r -- sh -c 'apk update && apk upgrade --no-interactive linux-samsung-gta8 && apk fix --no-interactive --reinstall linux-samsung-gta8'

	log "rebuilding initramfs and exporting boot.img"
	pmbootstrap initfs
	pmbootstrap export

	ls -lhL "$EXPORT_DIR/boot.img"
	strings "$(readlink -f "$EXPORT_DIR/boot.img")" | grep -m1 "Linux version " || true
}

run_heimdall() {
	local flash_rootfs=$1
	need heimdall

	if [ ! -e "$EXPORT_DIR/boot.img" ] || { [ "$flash_rootfs" = 1 ] && [ ! -e "$EXPORT_DIR/samsung-gta8.img" ]; }; then
		need pmbootstrap
		log "exporting missing images to $EXPORT_DIR"
		pmbootstrap export
	fi

	local boot_img rootfs_img=""
	boot_img="$(readlink -f "$EXPORT_DIR/boot.img")"
	[ -s "$boot_img" ] || die "missing or empty boot.img: $boot_img"

	local -a args=(flash --wait --boot "$boot_img")
	if [ "$flash_rootfs" = 1 ]; then
		rootfs_img="$(readlink -f "$EXPORT_DIR/samsung-gta8.img")"
		[ -s "$rootfs_img" ] || die "missing or empty rootfs image: $rootfs_img"
		args+=(--userdata "$rootfs_img")
	fi

	if [ "$WITH_DTBO" = 1 ]; then
		[ -s "$DTBO_IMG" ] || die "missing or empty dtbo-noop.img: $DTBO_IMG"
		args+=(--dtbo "$DTBO_IMG")
	fi

	if [ "$NO_REBOOT" = 1 ]; then
		args+=(--no-reboot)
	fi

	log "executing: heimdall ${args[*]}"
	heimdall "${args[@]}"
}

[ $# -gt 0 ] || usage 1
cmd=$1
shift

case $cmd in
build|install)
	if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
		usage 0
	fi
	if [ "${1:-}" = "--" ]; then
		shift
		INSTALL_ARGS=("$@")
	elif [ $# -gt 0 ]; then
		die "unexpected arguments for $cmd: $* (pass pmbootstrap install args after '--')"
	fi
	"cmd_$cmd"
	;;
build-kernel)
	[ $# -eq 0 ] || { [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && usage 0 || die "unexpected argument: $1"; }
	cmd_build_kernel
	;;
flash)
	parse_flash_and_install_args "$@"
	[ ${#INSTALL_ARGS[@]} -eq 0 ] || die "install args are not valid for flash"
	run_heimdall 1
	;;
flash-kernel)
	parse_flash_and_install_args "$@"
	[ ${#INSTALL_ARGS[@]} -eq 0 ] || die "install args are not valid for flash-kernel"
	run_heimdall 0
	;;
all)
	parse_flash_and_install_args "$@"
	cmd_build
	printf '\nPut the tablet into Samsung Download Mode and press Enter to flash...' >&2
	read -r _
	run_heimdall 1
	;;
-h|--help)
	usage 0
	;;
*)
	die "unknown subcommand: $cmd"
	;;
esac
