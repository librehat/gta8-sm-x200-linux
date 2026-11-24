#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Regenerate the (untracked) firmware/ reference files for the SM-X200/X205.
#
# Raw partition images are read from firmware/backups/ (git-ignored):
#   boot-device-backup.img      stock boot partition      (header only)
#   recovery-device-backup.img  recovery partition        (DT table with base SoC DT)
#   dtbo-device-backup.img      stock dtbo partition      (5-entry DT table)
#   device_live-raw.dtb         /sys/firmware/fdt as handed over by LK (optional)
#
# They can be populated with --pull (adb root shell, e.g. OrangeFox recovery)
# or --ap (Samsung AP_*.tar.md5 firmware package; no live FDT in that case).
#
# Generated in firmware/:
#   boot_header.bin, recovery_header.bin   first 64 KiB of each image
#   stock_dtb.img                          recovery DT table (base SoC DT)
#   stock_dtbo.img                         dtbo DT table without AVB footer
#   extracted_dtb/, extracted_dtbo/        dt_<n>_id_0x<id>.{dtb,dts} per entry
#   downstream_base.dts                    base SoC DT (extracted_dtb entry 0)
#   downstream_overlay.dts                 board overlay (dtbo entry --dtbo-idx)
#   downstream.dts                         base + overlay, concatenated
#   device_live.{dtb,dts}                  live FDT, device identifiers masked
#   dtbo-noop.img                          tools/dtbo-noop.dts as flashable dtbo
#
#   uwe5622/                               --pull-wireless: wcnmodem.bin & INIs
#
# usage: extract-firmware.sh [--pull | --ap AP_*.tar.md5] [--pull-wireless]
#                            [--force] [--in DIR] [--out DIR]
#                            [--dtbo-idx N] [--no-scrub]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
IN="$ROOT/firmware/backups"
OUT="$ROOT/firmware"
NOOP_DTS="$HERE/dtbo-noop.dts"

# Normal boot selects stock DTBO index 4 (id 0x1100); see firmware/boot_img_info.txt.
DTBO_IDX=4
DTBO_PART_SIZE=8388608
# Fixed salt keeps dtbo-noop.img reproducible (only the avbtool release string
# embedded in the vbmeta header varies between avbtool versions).
NOOP_SALT=a087e9a3effdab5240800ccfa64a5043de5b89479875b1c1f145ddbf294d822b
HEADER_BYTES=65536

PULL=0 PULL_WIRELESS=0 AP="" FORCE=0 SCRUB=1

usage() { sed -n '3,30s/^# \{0,1\}//p' "$0"; exit "${1:-0}"; }
log() { printf '>> %s\n' "$*" >&2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { for c; do command -v "$c" >/dev/null || die "missing tool: $c"; done; }

while [ $# -gt 0 ]; do
	case $1 in
	--pull) PULL=1 ;;
	--pull-wireless) PULL_WIRELESS=1 ;;
	--ap) AP=${2:?--ap needs a file}; shift ;;
	--force) FORCE=1 ;;
	--in) IN=${2:?}; shift ;;
	--out) OUT=${2:?}; shift ;;
	--dtbo-idx) DTBO_IDX=${2:?}; shift ;;
	--no-scrub) SCRUB=0 ;;
	-h|--help) usage 0 ;;
	*) usage 1 ;;
	esac
	shift
done
[ "$PULL" = 1 ] && [ -n "$AP" ] && die "--pull and --ap are mutually exclusive"

need dtc fdtget mkdtboimg avbtool unpack_bootimg python3 xxd

BOOT="$IN/boot-device-backup.img"
RECOVERY="$IN/recovery-device-backup.img"
DTBO="$IN/dtbo-device-backup.img"
LIVE="$IN/device_live-raw.dtb"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Never clobber existing dumps: once a custom boot/dtbo is flashed, a fresh
# pull would replace the only copy of the stock image. Missing files are still
# fetched, so e.g. a recovery dump can be added next to existing backups.
skip() {
	[ "$FORCE" = 0 ] && [ -e "$1" ] && { log "keeping existing $1"; return 0; }
	return 1
}

pull_adb() {
	need adb
	[ "$(adb shell id -u | tr -d '\r')" = 0 ] ||
		die "adb shell is not root; boot into OrangeFox/TWRP recovery first"
	mkdir -p "$IN"
	local p dev dst want got
	for p in boot recovery dtbo; do
		dev=/dev/block/by-name/$p dst="$IN/$p-device-backup.img"
		skip "$dst" && continue
		log "pulling $dev"
		adb exec-out cat "$dev" >"$TMP/$p.img"
		want=$(adb shell blockdev --getsize64 "$dev" | tr -d '\r')
		got=$(stat -c %s "$TMP/$p.img")
		[ "$want" = "$got" ] || die "$p: pulled $got bytes, partition is $want"
		mv "$TMP/$p.img" "$dst"
	done
	if ! skip "$LIVE"; then
		log "pulling /sys/firmware/fdt"
		adb exec-out cat /sys/firmware/fdt >"$TMP/live.dtb"
		mv "$TMP/live.dtb" "$LIVE"
	fi
}

unpack_ap() {
	need tar lz4
	[ -f "$AP" ] || die "$AP not found"
	mkdir -p "$IN"
	local p dst
	for p in boot recovery dtbo; do
		dst="$IN/$p-device-backup.img"
		skip "$dst" && continue
		log "unpacking $p.img.lz4 from $(basename "$AP")"
		tar -xOf "$AP" "$p.img.lz4" | lz4 -dc >"$TMP/$p.img"
		mv "$TMP/$p.img" "$dst"
	done
	warn "AP packages carry no live FDT; device_live.* comes from $LIVE if present"
}

magic() { xxd -l 4 -p "$1"; }

# Split an Android DT table (or a single plain FDT) into dt_<n>_id_0x<id>.*
dump_table() {
	local img=$1 dir=$2 info i name
	rm -rf "$dir"
	mkdir -p "$dir"
	case $(magic "$img") in
	d00dfeed)
		cp "$img" "$dir/dt_0_id_0x0.dtb"
		;;
	d7b7ab1e)
		info=$(mkdtboimg dump "$img" -b "$TMP/entry")
		local -a ids
		mapfile -t ids < <(awk '$1 == "id" { print $3 }' <<<"$info")
		[ "${#ids[@]}" -gt 0 ] || die "no entries in $img"
		for i in "${!ids[@]}"; do
			name=$(printf 'dt_%d_id_0x%x' "$i" "$((16#${ids[$i]}))")
			mv "$TMP/entry.$i" "$dir/$name.dtb"
		done
		;;
	*) die "$img: neither a DT table nor an FDT" ;;
	esac
	for i in "$dir"/*.dtb; do
		dtc -q -I dtb -O dts -o "${i%.dtb}.dts" "$i"
	done
}

# Mask per-device identifiers in place (same length, so the FDT stays valid).
scrub_fdt() {
	local dtb=$1 sn
	sn=$(fdtget -t s "$dtb" / serial-number 2>/dev/null || true)
	python3 - "$dtb" "$sn" <<'PY'
import re, sys
path, sn = sys.argv[1], sys.argv[2].encode()
data = open(path, "rb").read()
for key in (rb"androidboot\.serialno=", rb"androidboot\.un=", rb"androidboot\.em\.did="):
    data = re.sub(rb"(" + key + rb")([^ \x00]+)",
                  lambda m: m.group(1) + b"X" * len(m.group(2)), data)
if sn:
    data = data.replace(sn, b"0" * len(sn))
open(path, "wb").write(data)
PY
}

header() { head -c "$HEADER_BYTES" "$1" >"$2"; }

pull_wireless() {
	need adb
	[ "$(adb shell id -u | tr -d '\r')" = 0 ] ||
		die "adb shell is not root; boot into OrangeFox/TWRP recovery first"
	local wdir="$OUT/uwe5622" dev="/dev/block/by-name/wcnmodem" dst want got f path
	mkdir -p "$wdir"
	dst="$wdir/wcnmodem.bin"
	if ! skip "$dst"; then
		log "pulling $dev"
		adb exec-out cat "$dev" >"$TMP/wcnmodem.bin"
		want=$(adb shell blockdev --getsize64 "$dev" | tr -d '\r')
		got=$(stat -c %s "$TMP/wcnmodem.bin")
		[ "$want" = "$got" ] || die "wcnmodem: pulled $got bytes, partition is $want"
		mv "$TMP/wcnmodem.bin" "$dst"
	fi
	adb shell '[ -d /vendor/etc/wifi ] || mount /vendor 2>/dev/null || true'
	for f in /vendor/etc/wifi/wifi_board_config.ini \
		/vendor/etc/wifi_board_config.ini \
		/vendor/firmware/wifi_*.ini \
		/vendor/etc/wifi/wifi_*.ini \
		/vendor/etc/bt_configure_*.ini \
		/vendor/etc/bluetooth/bt_configure_*.ini; do
		for path in $(adb shell "ls -1 $f 2>/dev/null" | tr -d '\r'); do
			dst="$wdir/$(basename "$path")"
			skip "$dst" && continue
			log "pulling $path"
			adb exec-out cat "$path" >"$TMP/wireless.tmp"
			[ -s "$TMP/wireless.tmp" ] && mv "$TMP/wireless.tmp" "$dst"
		done
	done
	log "wireless firmware staged in $wdir"
}

[ "$PULL" = 1 ] && pull_adb
[ -n "$AP" ] && unpack_ap
[ "$PULL_WIRELESS" = 1 ] && pull_wireless
mkdir -p "$OUT"

if [ -f "$BOOT" ]; then
	log "boot: header"
	header "$BOOT" "$OUT/boot_header.bin"
else
	warn "$BOOT missing; skipping boot_header.bin"
fi

base_tab=""
if [ -f "$RECOVERY" ]; then
	log "recovery: header and base DT table"
	header "$RECOVERY" "$OUT/recovery_header.bin"
	unpack_bootimg --boot_img "$RECOVERY" --out "$TMP/recovery" >/dev/null
	base_tab="$TMP/recovery/dtb"
fi
if [ -n "$base_tab" ] && [ -s "$base_tab" ]; then
	cp "$base_tab" "$OUT/stock_dtb.img"
	dump_table "$OUT/stock_dtb.img" "$OUT/extracted_dtb"
else
	# The stock boot dtb section is a small stub, not the base SoC DT.
	warn "no recovery dtb section; skipping stock_dtb.img and extracted_dtb/"
fi

if [ -f "$DTBO" ]; then
	log "dtbo: DT table"
	[ "$(magic "$DTBO")" = d7b7ab1e ] || die "$DTBO is not a DT table"
	head -c "$((16#$(xxd -s 4 -l 4 -p "$DTBO")))" "$DTBO" >"$OUT/stock_dtbo.img"
	dump_table "$OUT/stock_dtbo.img" "$OUT/extracted_dtbo"
else
	warn "$DTBO missing; skipping stock_dtbo.img and extracted_dtbo/"
fi

base=$(compgen -G "$OUT/extracted_dtb/dt_0_id_*.dts" || true)
overlay=$(compgen -G "$OUT/extracted_dtbo/dt_${DTBO_IDX}_id_*.dts" || true)
if [ -n "$base" ] && [ -n "$overlay" ]; then
	ov_id=${overlay##*_id_}
	ov_id=${ov_id%.dts}
	[ "$ov_id" = 0x1100 ] || warn "DTBO entry $DTBO_IDX has id $ov_id, not 0x1100"
	log "downstream DTS: base + dtbo entry $DTBO_IDX ($ov_id)"
	cp "$base" "$OUT/downstream_base.dts"
	cp "$overlay" "$OUT/downstream_overlay.dts"
	{
		echo "/* Base SoC DTS: Unisoc UMS512 (SharkL5Pro) */"
		cat "$base"
		echo
		echo
		echo "/* Board Overlay DTS: Samsung Galaxy Tab A8 SM-X200/X205 (id=$ov_id) */"
		cat "$overlay"
	} >"$OUT/downstream.dts"
else
	warn "base DT or dtbo entry $DTBO_IDX missing; skipping downstream*.dts"
fi

if [ -f "$LIVE" ]; then
	log "live FDT$([ "$SCRUB" = 1 ] && echo ' (masking device identifiers)')"
	cp "$LIVE" "$OUT/device_live.dtb"
	[ "$SCRUB" = 1 ] && scrub_fdt "$OUT/device_live.dtb"
	dtc -q -I dtb -O dts -o "$OUT/device_live.dts" "$OUT/device_live.dtb"
else
	warn "$LIVE missing; skipping device_live.*"
fi

log "dtbo-noop.img from $(basename "$NOOP_DTS")"
dtc -q -I dts -O dtb -o "$TMP/noop.dtb" "$NOOP_DTS"
mkdtboimg create "$TMP/noop.img" --page_size=2048 "$TMP/noop.dtb" --id=0x1100
avbtool add_hash_footer --image "$TMP/noop.img" --partition_name dtbo \
	--partition_size "$DTBO_PART_SIZE" --salt "$NOOP_SALT"
mv "$TMP/noop.img" "$OUT/dtbo-noop.img"

log "done: $OUT"
