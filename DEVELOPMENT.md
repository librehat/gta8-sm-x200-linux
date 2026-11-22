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
| Kernel build | `build-essential`, `gcc-aarch64-linux-gnu`, `bison`, `flex`, `bc`, `pkgconf`, `libssl-dev`, `libelf-dev`, `libncurses-dev`, `cpio`, `kmod`, `rsync` | Cross-compiling `Image.gz` and the DTB (`ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-`) |
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
| `linux-samsung-gtaba8/` | `torvalds/linux` tag `v7.3`, plus cherry-picks from Otto Pflüger's `ums9230-mainline` (Codeberg) and custom patches |
| `pmaports/` | Nura Edge `pmaports`, `master` branch (rolling `edge` channel) |
| `firmware/` | Stock Samsung `boot.img`, decompiled downstream DTS, `hardware_map.txt` |

## 4. One-Time Setup

1. **USB permissions.** Heimdall and ADB need udev access to the tablet.
   ```bash
   sudo usermod -aG plugdev $USER     # then log out and back in
   ```
   Android udev rules (`android-udev-rules`) are pulled in with `adb`. Check that `heimdall` can open the device in Download mode.
2. **Initialise `pmbootstrap`.**
   ```bash
   pmbootstrap init                   # channel: edge; device: samsung-gtaba8 (once it exists)
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

# Kernel smoke test (from linux-samsung-gtaba8/)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image.gz
```

## 6. Standard Build Commands

```bash
# Kernel + DTB (in linux-samsung-gtaba8/)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image.gz sprd/ums512-samsung-gtaba8.dtb

# DT binding validation
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CHECK_DTBS=y sprd/ums512-samsung-gtaba8.dtb

# Nura packages and boot image
pmbootstrap checksum device-samsung-gtaba8 linux-samsung-gtaba8
pmbootstrap build device-samsung-gtaba8 --force
pmbootstrap build linux-samsung-gtaba8 --force
pmbootstrap initfs
```

## 7. Flashing & Hardware Testing (manual)

Flashing is always done by the user, never by an agent.

```bash
pmbootstrap flasher flash_kernel                 # Samsung Download mode via heimdall
sudo ip addr add 172.16.42.2/24 dev <usb-iface>  # after the gadget enumerates
ssh root@172.16.42.1
```

Save `ramoops`/`pstore`, `dmesg`, `lsusb` and `ip link` output to `logs/` for diagnosis.