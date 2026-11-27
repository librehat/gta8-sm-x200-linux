# Installing Nura Edge on Samsung Galaxy Tab A8 (`SM-X200`)

This guide explains how to install and flash **Nura Edge** (postmarketOS-based Linux with mainline kernel) onto the **Samsung Galaxy Tab A8 10.5 (2021)** (`SM-X200`).

> [!WARNING]
> **Flashing `rootfs.img` to `userdata` and unlocking the bootloader will wipe all data on the tablet.** Back up any important files before starting. This port is currently in **alpha** — check [`README.md`](README.md) for the list of working and unsupported hardware (Audio, Camera, Sensors, and USB OTG are not working yet).

---

## 1. Prerequisites (Coming from Stock One UI)

Before flashing Nura Edge onto a tablet running Stock Samsung One UI, complete the following steps:

### A. Unlock the Bootloader (OEM Unlocking)

1. Boot into Stock One UI and connect the tablet to **Wi-Fi** (Samsung's security checks may hide the *OEM unlocking* toggle until the device has checked in online).
2. Enable **Developer options**:
   - Open **Settings → About tablet → Software information**.
   - Tap **Build number** 7 times until *Developer mode has been turned on* appears.
3. Open **Settings → Developer options** and toggle **OEM unlocking** ON.
4. Power off the tablet completely.
5. Boot into **Samsung Download Mode**:
   - Press and hold **Volume Up + Volume Down** together, then plug in a USB cable connected to your PC.
6. At the teal warning screen, **long-press Volume Up** to enter *Device Unlock Mode*, then press **Volume Up** again to confirm unlocking the bootloader.
   - The tablet will wipe all user data and reboot.
7. Once back in One UI setup, complete (or skip through) setup and verify under **Developer options** that **OEM unlocking** shows as enabled/unlocked.

### B. Disable Android Verified Boot (`vbmeta`) if Coming Directly from Stock

Even with an unlocked bootloader, Stock One UI's `vbmeta` partition enforces Android Verified Boot checks across `boot` and `dtbo`. While Nura Edge's `boot.img` and `dtbo.img` include AVB v1.0 `--algorithm NONE` hash footers expected by Samsung's Little Kernel (`LK`) bootloader, an unmodified stock `vbmeta` partition can reject non-Samsung images.

If you have not already flashed a disabled `vbmeta` image (for example, while installing OrangeFox/TWRP recovery), generate one with `avbtool` (`android-tools-avbtool`):

```bash
avbtool make_vbmeta_image --flags 2 --padding_size 4096 --output vbmeta-disabled.img
```

You can then include `--vbmeta vbmeta-disabled.img` in the `heimdall flash` command below.

### C. Why `dtbo.img` (`dtbo-noop.img`) is Mandatory

Samsung's `LK` bootloader automatically selects a stock DTBO overlay (`board_id 0x1100`) and merges it into the Device Tree before booting Linux. Merging the stock Android DTBO corrupts a mainline Device Tree and prevents booting.

Flashing Nura Edge's empty `dtbo.img` (`dtbo-noop.img`) to the `dtbo` partition is **mandatory** on your first install and any time after restoring stock One UI firmware.

---

## 2. Host Requirements

### Linux (Recommended)

Install `heimdall` and standard archive/networking utilities (on Ubuntu/Debian):

```bash
sudo apt update && sudo apt install -y heimdall-flash xz-utils iproute2 openssh-client usbutils
```

If `heimdall` reports permission errors accessing the USB device in Download Mode, add your user to the `plugdev` group (and ensure `android-udev-rules` or equivalent udev rules are installed), then log out and back in:

```bash
sudo usermod -aG plugdev "$USER"
```

*(See [`DEVELOPMENT.md`](DEVELOPMENT.md) for full build host dependencies if compiling from source.)*

---

## 3. Option A: Flash a Pre-Built Release Archive

### 1. Download, Verify, and Extract

Verify the release tarball checksum, extract it, and verify the inner partition images:

```bash
sha256sum -c nura-edge-samsung-gta8-<version>.tar.xz.sha256
tar -xJf nura-edge-samsung-gta8-<version>.tar.xz
cd nura-edge-samsung-gta8-<version>
sha256sum -c SHA256SUMS
```

The extracted directory contains:
- `boot.img` — Linux kernel (with 2 MiB LK relocation shim), UMS512 DTB, and initramfs
- `rootfs.img` — Nura Edge (`samsung-gta8`) root filesystem
- `dtbo.img` — Mandatory no-op DTBO image (`dtbo-noop.img`)
- `odin-boot.tar` *(present if built with `--odin`)* — Odin-compatible archive of `boot.img` and `dtbo.img`

### 2. Enter Download Mode

1. Power off the tablet completely.
2. Hold **Volume Up + Volume Down** and connect the USB cable to your PC.
3. Press **Volume Up** once at the warning screen to enter **Download Mode**.

### 3. Flash via Heimdall (Linux / macOS)

Run `heimdall` from the extracted release directory:

```bash
heimdall flash --wait --boot boot.img --userdata rootfs.img --dtbo dtbo.img
```

If you are flashing directly over unmodified Stock One UI and need to disable `vbmeta` verification at the same time, include `--vbmeta`:

```bash
heimdall flash --wait --boot boot.img --userdata rootfs.img --dtbo dtbo.img --vbmeta vbmeta-disabled.img
```

The tablet will reboot automatically when flashing finishes.

> [!NOTE]
> **Windows / Odin users:** If your release archive includes `odin-boot.tar`, it can be flashed in Odin's `AP` slot to write `boot.img` and `dtbo.img`. However, `rootfs.img` is a raw filesystem image (not wrapped in an Odin `.tar`), so Linux `heimdall` is the recommended flashing method.

---

## 4. Option B: Build and Flash from Source

If you are building images locally from this repository (see [`DEVELOPMENT.md`](DEVELOPMENT.md) for toolchain setup):

1. **Extract proprietary wireless and touchscreen firmware** from the tablet (booted into OrangeFox/TWRP root `adb`) or a Samsung `AP_*.tar.md5` package:

   ```bash
   ./tools/extract-firmware.sh --pull --pull-wireless --pull-touchscreen
   ```

2. **Build all packages and rootfs/boot images:**

   ```bash
   ./tools/flash-gta8.sh build
   ```

3. **Enter Download Mode on the tablet and flash everything (including `dtbo-noop.img`):**

   ```bash
   ./tools/flash-gta8.sh flash --with-dtbo
   ```

4. **Subsequent kernel-only updates** (without wiping/reflashing `userdata`):

   ```bash
   ./tools/flash-gta8.sh build-kernel
   ./tools/flash-gta8.sh flash-kernel
   ```

---

## 5. First Boot, Login & USB SSH Access

- **First boot:** After `heimdall` completes, the tablet should display the Nura Edge / Plasma Mobile environment in landscape orientation (`1920×1200` at 150% scaling).
- **Default credentials:**
  - **Username:** `user`
  - **Password:** `147147` *(recommended: change immediately after logging in with `passwd`)*

### Connecting via USB Gadget Networking (SSH)

The tablet exposes a ConfigFS USB network gadget (`RNDIS` / `ACM`) at `172.16.42.1/24`.

On a Linux host, bring up the host-side interface using the helper script:

```bash
./tools/usbnet-up.sh
ssh user@172.16.42.1
```

Or configure the USB network interface manually:

```bash
sudo ip addr add 172.16.42.2/24 dev <usb-iface>
sudo ip link set <usb-iface> up
ssh user@172.16.42.1
```

*(If the boot stops in the initramfs debug shell before switching root, SSH/telnet uses `root@172.16.42.1`.)*

---

## 6. Troubleshooting & Restoring Stock Firmware

### Early Boot Failures (`ramoops` / `pstore`)

If the tablet fails to boot before USB networking comes up, `ramoops` preserves the last kernel console and panic log across warm reboots (`0xfff80000`, `256 KiB`):

1. Force a warm reboot into recovery (hold **Power + Volume Down** for ~7 seconds, then switch to **Volume Up** as the screen goes black if you have OrangeFox/TWRP installed) or boot back into Android.
2. Inspect `/sys/fs/pstore/` (`console-ramoops-0`, `dmesg-ramoops-*`) to diagnose the crash.

### Returning to Stock One UI

To return to Stock Samsung One UI, boot into Download Mode and flash an official Samsung firmware package (`AP`, `BL`, `CSC`) for your exact model (`SM-X200` / `SM-X205`) and binary/bootloader revision using Odin or Heimdall. This restores the stock `boot`, `dtbo`, `vbmeta`, and `userdata` partitions.
