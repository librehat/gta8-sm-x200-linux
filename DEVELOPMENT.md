# DEVELOPMENT.md — Host Setup

Host requirements for building Nura Edge (postmarketOS-based) with a mainline Linux kernel for the Samsung Galaxy Tab A8 10.5 (2021), `SM-X200` / `SM-X205` (Unisoc T618 / `UMS512`).

**Reference host:** Ubuntu 26.04 LTS (`resolute`), x86_64, with `sudo` access.

---

## 1. Required Packages (APT)

```bash
sudo apt update && sudo apt install -y \
    build-essential git bc cpio kmod rsync \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    bison flex pkgconf libssl-dev libelf-dev libncurses-dev \
    device-tree-compiler yamllint \
    python3-pip pipx \
    pmbootstrap qemu-user qemu-user-binfmt \
    mkbootimg abootimg heimdall-flash \
    adb fastboot android-sdk-libsparse-utils \
    iproute2 openssh-client usbutils screen
```

| Group | Packages | Used for |
| :--- | :--- | :--- |
| Kernel build | `build-essential`, `gcc-aarch64-linux-gnu`, `bison`, `flex`, `bc`, `pkgconf`, `libssl-dev`, `libelf-dev`, `libncurses-dev`, `cpio`, `kmod`, `rsync` | Cross-compiling `Image` and the DTB (`ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-`) |
| Devicetree | `device-tree-compiler`, `yamllint` | Compiling DTS and YAML binding checks |
| Nura packaging | `pmbootstrap`, `qemu-user`, `qemu-user-binfmt` | Building aarch64 packages, chroots and `initfs` |
| Boot image / flashing | `mkbootimg`, `abootimg`, `heimdall-flash`, `adb`, `fastboot`, `android-sdk-libsparse-utils` | Unpacking the stock `boot.img`, building a Samsung `boot.img`, flashing in Download mode |
| Host diagnostics | `iproute2`, `openssh-client`, `usbutils`, `screen` | USB gadget networking (`172.16.42.x`), SSH, `lsusb`, serial console |

> [!NOTE]
> On Ubuntu 26.04, `qemu-user-static` and `binfmt-support` are replaced by `qemu-user` and `qemu-user-binfmt`.

## 2. Python Tools (pipx)

`dtschema` isn't packaged in APT. Install it with pipx. It provides `dt-validate` for `CHECK_DTBS=y`.

```bash
pipx install dtschema
pipx ensurepath        # makes sure ~/.local/bin is on PATH
```

## 3. Source Trees

| Path | Source |
| :--- | :--- |
| `linux/` | `torvalds/linux` tag `v7.3` LTS, plus cherry-picks from Otto Pflüger's `ums9230-mainline` (Codeberg), board/DPU/touch patches, and the isolated out-of-tree `uwe5622` wireless driver (sourced from Armbian's `sprd-ums512` tree) |
| `pmaports/` | Nura Edge `pmaports`, `master` branch (rolling `edge` channel) |
| `firmware/` | Stock Samsung `boot.img`, decompiled downstream DTS, `hardware_map.txt`, `boot_img_info.txt`, and extracted wireless/touchscreen firmware |

### Repository & Commit Hygiene

- **Decoupled Repositories:** `linux/` and `pmaports/` are maintained as separate Git repositories to simplify kernel rebasing and eventual upstreaming to LKML and Nura's shared `linux-postmarketos-unisoc-*` / `linux-postmarketos-sprd` packaging.
- **Kernel Commit Layering:** Keep `linux/` history cleanly layered so mainline patches remain easy to rebase or extract:
  1. Mainline Linux `v7.3` LTS baseline (native `UMS512` clocks/pinctrl/storage/serial and `SC2730` PMIC regulators).
  2. Cherry-picked `ums9230-mainline` and shared Unisoc driver fixes (`phy-sprd-usb2`, `musb-sprd`, `sdhci-sprd`, `spi-sprd`, `i2c-sprd`, `clk-sprd`, `sc27xx`).
  3. Board-specific commits (`ums512-samsung-gta8.dts`, `ums512_dpu_kms`, `nt36xxx`).
  4. Isolated out-of-tree `uwe5622` wireless commits (`drivers/net/wireless/uwe5622/`).

### `pmaports` Packages (`pmaports/device/testing/`)

- **`device-samsung-gta8`**: Board metadata (`deviceinfo` with `chassis="tablet"`, `heimdall-bootimg`, `mkbootimg` v2 offsets, ConfigFS RNDIS), `kernel-cmdline.conf`, `postprocess-bootimg.sh` (appends the AVB hash footer), and `sprd-bt-attach` + OpenRC service (`device-samsung-gta8-openrc`).
- **`linux-samsung-gta8`**: `APKBUILD`, `config-samsung-gta8.aarch64`, and `reloc.S`. Builds uncompressed `Image`, prepends the 2 MiB alignment relocation stub, wraps the DTB in an Android DT table, and accepts `--src="$PWD/linux"` for local kernel builds.
- **`firmware-samsung-gta8`**: Packages proprietary `UWE5622` wireless/BT firmware and Novatek `NT36523B` touchscreen firmware (bundling the touchscreen `.bin` into initramfs via `mkinitfs`).

## 4. One-Time Setup

1. **USB permissions.** Heimdall and ADB need udev access to the tablet.
   ```bash
   sudo usermod -aG plugdev $USER     # then log out and back in
   ```
   Android udev rules (`android-udev-rules`) are pulled in with `adb`. Check that `heimdall` can open the device in Download mode.
2. **Initialise `pmbootstrap`.**
   ```bash
   pmbootstrap init                   # channel: edge; device: samsung-gta8 (once it exists)
   ```
   Point `pmbootstrap` at the local `pmaports/` checkout when prompted. Alternatively, run `pmbootstrap --aports <path>`.
3. **Verify the `binfmt` registration** for aarch64 chroots:
   ```bash
   ls /proc/sys/fs/binfmt_misc/ | grep qemu-aarch64
   ```
4. **Extract device firmware.** Read `firmware/README.md` for more details.

## 5. Verification

```bash
# Toolchain
aarch64-linux-gnu-gcc --version
dtc --version
dt-validate --version
pmbootstrap --version
heimdall version
mkbootimg --help | head -n 1
abootimg 2>&1 | head -n 1
command -v qemu-aarch64

# Kernel smoke test (from linux/)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image
```

## 6. Standard Build Commands

```bash
# Kernel + DTB (in linux/)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image sprd/ums512-samsung-gta8.dtb

# DT binding validation (in linux/)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CHECK_DTBS=y sprd/ums512-samsung-gta8.dtb

# Recommended repository build helpers (stages firmware, builds from ./linux, exports images)
./tools/flash-gta8.sh build         # full build: firmware + device + local kernel + rootfs image
./tools/flash-gta8.sh build-kernel  # fast kernel/initramfs-only rebuild (no rootfs rebuild)

# Equivalent manual pmbootstrap commands (stage firmware first with tools/extract-firmware.sh)
pmbootstrap checksum device-samsung-gta8 linux-samsung-gta8
pmbootstrap build firmware-samsung-gta8 --src="$PWD/firmware" --force
pmbootstrap build device-samsung-gta8 --force
pmbootstrap build linux-samsung-gta8 --src="$PWD/linux" --force
pmbootstrap initfs
```

## 7. Flashing & Hardware Testing (manual)

Flashing is always done by the user, never by an agent.

```bash
# Full flash including dtbo-noop.img (required on first flash or after stock restores)
./tools/flash-gta8.sh flash --with-dtbo

# Fast kernel-only iteration loop (rebuilds boot.img without reflashing rootfs)
./tools/flash-gta8.sh build-kernel
./tools/flash-gta8.sh flash-kernel
# Or via pmbootstrap directly:
#   pmbootstrap build linux-samsung-gta8 --src="$PWD/linux" --force && pmbootstrap initfs && pmbootstrap flasher flash_kernel

# Bring up host-side USB gadget networking (auto-detects interface, sets 172.16.42.2/24)
./tools/usbnet-up.sh
# Or manually:
#   sudo ip addr add 172.16.42.2/24 dev <usb-iface>

ssh user@172.16.42.1   # installed Nura Edge rootfs (use root@172.16.42.1 or telnet in initramfs)
```

### Crash & Diagnostic Log Collection

- **Before USB networking is active (early boot panic / hang):** Reboot into recovery (OrangeFox/TWRP) or stock OS and pull persistent `pstore`/`ramoops` logs from `/sys/fs/pstore/` into `logs/`.
- **Once USB networking is active:** Stream live kernel logs over SSH with `dmesg -w`, and save `dmesg`, `lsusb`, and `ip link` output to `logs/` for diagnosis.