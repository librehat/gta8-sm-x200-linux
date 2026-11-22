#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
GEN_INIT_CPIO="$ROOT/linux/usr/gen_init_cpio"
APK_DIR="$ROOT/dist/alpine-apks"
OUT_CPIO_GZ="$ROOT/dist/initramfs-phase3.cpio.gz"

BASE_URL="https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64"
APKS="
busybox-static-1.38.0-r8.apk
musl-1.2.6-r6.apk
zlib-1.4-r0.apk
skalibs-libs-2.16.0.0-r0.apk
utmps-libs-0.1.3.4-r1.apk
dropbear-2026.94-r0.apk
"

[ -x "$GEN_INIT_CPIO" ] || { echo "Missing $GEN_INIT_CPIO" >&2; exit 1; }

mkdir -p "$APK_DIR" "$ROOT/dist"
for pkg in $APKS; do
	if [ ! -s "$APK_DIR/$pkg" ]; then
		echo ">> Downloading $pkg"
		curl -fsSL -o "$APK_DIR/$pkg" "$BASE_URL/$pkg"
	fi
done

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
STAGE="$T/root"
mkdir -p "$STAGE"/{bin,sbin,usr/bin,usr/sbin,lib,usr/lib,etc/dropbear,root/.ssh,proc,sys,dev/pts,dev/shm,tmp,run,var/log,mnt,newroot}
ln -s /run "$STAGE/var/run"

for pkg in $APKS; do
	tar -xzf "$APK_DIR/$pkg" -C "$STAGE" 2>/dev/null || tar -xzf "$APK_DIR/$pkg" -C "$STAGE"
done
rm -f "$STAGE"/.PKGINFO "$STAGE"/.SIGN.* "$STAGE"/.post-install "$STAGE"/.pre-install 2>/dev/null || true

install -m755 "$STAGE/bin/busybox.static" "$STAGE/bin/busybox"
rm -f "$STAGE/bin/busybox.static"

APPLETS="
sh ash mount umount ip ifconfig dmesg ls cat ps sleep mkdir ln echo
reboot poweroff sync blkid fdisk chroot mknod grep awk sed vi top free uname
hostname chmod chown rm cp mv tar gzip setsid cttyhack getty telnetd passwd
find head tail wc kill killall id env ping df stat touch cut sort tr tee readlink
stty mountpoint arp netstat route pidof
"
for app in $APPLETS; do
	ln -sf busybox "$STAGE/bin/$app"
done

# Verify required Dropbear binary & shared libraries exist
for f in \
	usr/sbin/dropbear \
	usr/bin/dropbearkey \
	lib/ld-musl-aarch64.so.1 \
	lib/libc.musl-aarch64.so.1 \
	usr/lib/libz.so.1 \
	usr/lib/libutmps.so.0.1 \
	usr/lib/libskarnet.so.2.16
do
	[ -e "$STAGE/$f" ] || { echo "Missing required file in staging: $f" >&2; exit 1; }
done

cat <<'EOF' > "$STAGE/etc/passwd"
root:x:0:0:root:/root:/bin/sh
EOF

cat <<'EOF' > "$STAGE/etc/group"
root:x:0:
EOF

cat <<'EOF' > "$STAGE/etc/shadow"
root::0:0:99999:7:::
EOF
chmod 0640 "$STAGE/etc/shadow"

cat <<'EOF' > "$STAGE/etc/shells"
/bin/sh
/bin/ash
EOF

if ls "$HOME"/.ssh/*.pub >/dev/null 2>&1; then
	cat "$HOME"/.ssh/*.pub > "$STAGE/root/.ssh/authorized_keys"
	chmod 0600 "$STAGE/root/.ssh/authorized_keys"
fi
chmod 0700 "$STAGE/root" "$STAGE/root/.ssh"

cat <<'EOF' > "$STAGE/init"
#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export TERM=vt100
export PS1='root@gtaba8:\w# '

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mountpoint -q /dev || mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm /tmp /run /var/log
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /tmp
mount -t tmpfs tmpfs /run
mount -t configfs none /sys/kernel/config 2>/dev/null || true

hostname samsung-gtaba8
ip link set lo up
ip addr add 127.0.0.1/8 dev lo 2>/dev/null || true

log() {
	echo "gta8-init: $*" > /dev/kmsg 2>/dev/null || true
	echo "$*" > /dev/tty0 2>/dev/null || true
}

log "=== Nura Edge Bring-Up Initramfs (Linux $(uname -r)) ==="

{
	echo "[Hardware Bring-Up Status]"
	dmesg | grep -iE "musb|hsphy|sc2730|mmc|gpio-keys|simplefb" | tail -n 12
	echo ""
} > /dev/tty0 2>/dev/null || true

UDC=""
i=0
while [ "$i" -lt 80 ]; do
	for u in /sys/class/udc/*; do
		if [ -e "$u" ]; then
			UDC="${u##*/}"
			break
		fi
	done
	[ -n "$UDC" ] && break
	sleep 0.1
	i=$((i + 1))
done

if [ -n "$UDC" ] && [ -d /sys/kernel/config/usb_gadget ]; then
	G=/sys/kernel/config/usb_gadget/g1
	mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409"
	echo 0x18d1 > "$G/idVendor"
	echo 0xd001 > "$G/idProduct"
	echo 0x0100 > "$G/bcdDevice"
	echo 0x0200 > "$G/bcdUSB"
	echo 0xEF > "$G/bDeviceClass"
	echo 0x02 > "$G/bDeviceSubClass"
	echo 0x01 > "$G/bDeviceProtocol"
	echo "Nura Edge" > "$G/strings/0x409/manufacturer"
	echo "Samsung Galaxy Tab A8 (v7.3)" > "$G/strings/0x409/product"
	echo "gta8-v7.3" > "$G/strings/0x409/serialnumber"
	echo "RNDIS + ACM" > "$G/configs/c.1/strings/0x409/configuration"
	echo 500 > "$G/configs/c.1/MaxPower"

	mkdir -p "$G/functions/rndis.usb0"
	echo "02:00:00:12:34:56" > "$G/functions/rndis.usb0/dev_addr"
	echo "02:00:00:12:34:57" > "$G/functions/rndis.usb0/host_addr"
	ln -s "$G/functions/rndis.usb0" "$G/configs/c.1/"

	mkdir -p "$G/functions/acm.GS0"
	ln -s "$G/functions/acm.GS0" "$G/configs/c.1/"

	echo "$UDC" > "$G/UDC"
	log "USB gadget bound to UDC: $UDC"
else
	log "WARNING: No UDC or configfs found!"
fi

i=0
while [ "$i" -lt 50 ]; do
	[ -d /sys/class/net/usb0 ] && break
	sleep 0.1
	i=$((i + 1))
done

if [ -d /sys/class/net/usb0 ]; then
	ip link set usb0 up
	ip addr add 172.16.42.1/24 dev usb0 2>/dev/null || true
	log "usb0 UP: 172.16.42.1/24 (static; set host to 172.16.42.2/24)"
else
	log "WARNING: usb0 interface did not appear"
fi

if dropbear -R -E -B -p 22 >/tmp/dropbear.log 2>&1; then
	log "Dropbear SSH listening on 172.16.42.1:22"
else
	log "WARNING: Dropbear failed to start (see /tmp/dropbear.log)"
fi

PARTS=$(ls /dev/mmcblk0p* 2>/dev/null | wc -l)
log "Storage: /dev/mmcblk0 partitions detected: $PARTS"
log "Fallback serial shell active on /dev/ttyGS0 (host /dev/ttyACM0)"

(
	while true; do
		if [ -c /dev/ttyGS0 ]; then
			stty -F /dev/ttyGS0 sane 115200 2>/dev/null || true
			printf '\r\n=== Samsung Galaxy Tab A8 (v7.3) USB Serial Shell ===\r\n' > /dev/ttyGS0 2>/dev/null || true
			printf 'Press Enter for prompt. Try: ip a; ls /dev/mmcblk0*; reboot recovery\r\n\r\n' > /dev/ttyGS0 2>/dev/null || true
			sh -i </dev/ttyGS0 >/dev/ttyGS0 2>&1 || true
			log "ttyGS0 shell exited, respawning..."
		fi
		sleep 1
	done
) &

(
	for d in 5 10 15; do
		sleep "$d"
		OP="$(cat /sys/class/net/usb0/operstate 2>/dev/null || echo missing)"
		CAR="$(cat /sys/class/net/usb0/carrier 2>/dev/null || echo -)"
		RXP="$(cat /sys/class/net/usb0/statistics/rx_packets 2>/dev/null || echo -)"
		RXE="$(cat /sys/class/net/usb0/statistics/rx_errors 2>/dev/null || echo -)"
		RXB="$(cat /sys/class/net/usb0/statistics/rx_bytes 2>/dev/null || echo -)"
		TXP="$(cat /sys/class/net/usb0/statistics/tx_packets 2>/dev/null || echo -)"
		TXE="$(cat /sys/class/net/usb0/statistics/tx_errors 2>/dev/null || echo -)"
		TXB="$(cat /sys/class/net/usb0/statistics/tx_bytes 2>/dev/null || echo -)"
		DBP="$(pidof dropbear 2>/dev/null || echo none)"
		UST="$(cat /sys/class/udc/"$UDC"/state 2>/dev/null || echo -)"
		USP="$(cat /sys/class/udc/"$UDC"/current_speed 2>/dev/null || echo -)"
		BLK="$(ls /dev/mmcblk* 2>/dev/null | wc -l)"
		EVS="$(ls /dev/input/event* 2>/dev/null | tr '\n' ' ')"
		log "diag: udc=$UST($USP) usb0=$OP carrier=$CAR rx=$RXP(err=$RXE,b=$RXB) tx=$TXP(err=$TXE,b=$TXB) dropbear=$DBP blk=$BLK input=${EVS:-none}"
		grep -iE 'musb|5fff' /proc/interrupts 2>/dev/null | while IFS= read -r line; do
			[ -n "$line" ] && log "diag(irq): $line"
		done
		if [ -s /tmp/dropbear.log ]; then
			while IFS= read -r line; do
				[ -n "$line" ] && log "diag(dropbear.log): $line"
			done < /tmp/dropbear.log
		fi
	done
) &

while true; do
	sleep 60
done
EOF
chmod 0755 "$STAGE/init"

LIST="$T/initramfs.list"
{
	echo "dir /dev 0755 0 0"
	echo "nod /dev/console 0600 0 0 c 5 1"
	echo "nod /dev/null 0666 0 0 c 1 3"
	echo "nod /dev/zero 0666 0 0 c 1 5"
	echo "nod /dev/random 0666 0 0 c 1 8"
	echo "nod /dev/urandom 0666 0 0 c 1 9"
	echo "nod /dev/kmsg 0644 0 0 c 1 11"
	echo "nod /dev/tty0 0620 0 0 c 4 0"
	(cd "$STAGE" && find . -mindepth 1 ! -path ./dev ! -path './dev/pts*' ! -path './dev/shm*' | sort) |
	while read -r f; do
		p="${f#.}"
		src="$STAGE$p"
		m="$(stat -c %a "$src")"
		if [ -L "$src" ]; then
			echo "slink $p $(readlink "$src") $m 0 0"
		elif [ -d "$src" ]; then
			echo "dir $p $m 0 0"
		else
			echo "file $p $src $m 0 0"
		fi
	done
	echo "dir /dev/pts 0755 0 0"
	echo "dir /dev/shm 1777 0 0"
} > "$LIST"

"$GEN_INIT_CPIO" "$LIST" | gzip -9 > "$OUT_CPIO_GZ"
echo "Wrote $OUT_CPIO_GZ ($(stat -c%s "$OUT_CPIO_GZ") bytes)"
