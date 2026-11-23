# High-Level Porting Plan: Nura Edge on Samsung Galaxy Tab A8 2021 (Linux v7.3 LTS)

This document outlines the architecture, kernel branching strategy, phased bring-up roadmap, and development workflow for porting **Nura Edge** (formerly postmarketOS) to the **Samsung Galaxy Tab A8 10.5 (2021)** using **Linux v7.3 LTS** as the kernel baseline.

---

## 1. Target Hardware Profile

| Component | Specification | Upstream / Mainline Notes |
| :--- | :--- | :--- |
| **Device** | Samsung Galaxy Tab A8 10.5 (2021) | Models `SM-X200` (Wi-Fi) and `SM-X205` (LTE) |
| **SoC** | Unisoc Tiger T618 (`UMS512` / `sharkl5pro`) | Upstream architecture files live under `arch/arm64/boot/dts/sprd/` |
| **CPU** | 2× ARM Cortex-A75 + 6× ARM Cortex-A55 (`aarch64`) | SMP, GICv3, and arch timers supported natively in `v7.3` |
| **PMIC** | Unisoc `SC2730` | Regulator driver (`CONFIG_REGULATOR_SC2730`) merged in `v7.3` |
| **GPU** | ARM Mali-G52 MP2 (Bifrost) | Open-source Mesa `panfrost` driver (`CONFIG_DRM_PANFROST`) |
| **Storage / RAM** | eMMC 5.1 (`sdhci-sprd`) / 3GB or 4GB LPDDR4X | Supported natively in `v7.3` |
| **Wireless** | Unisoc `UWE5622` (Marlin3 Wi-Fi/BT/GNSS) | Out-of-tree driver; isolate until core bring-up is complete |

---

## 2. Kernel Strategy (`v7.3` LTS + Staging Delta)

Basing your fork on the `v7.3` LTS tag gives you a long-term supported baseline with native Unisoc `UMS512` and `SC2730` PMIC support, while allowing you to cherry-pick remaining peripheral patchsets from Otto Pflüger's `ums9230-mainline` staging tree on Codeberg.

### Layer 1: Native in Linux `v7.3` LTS (No Patches Required)
* **PMIC & Voltage Rails:** Native `SC2730` regulator driver (`drivers/regulator/sc2730-regulator.c`) for CPU clusters, memory, and I/O power domains.
* **SoC Core & Buses:** `ums512` clocks (`drivers/clk/sprd/`), pinctrl (`drivers/pinctrl/sprd/`), `sprd-mailbox`, `sprd-dma`, I2C, and SPI.
* **Early Debug & Storage:** `sprd-serial` (`earlycon` / UART), `pstore`/`ramoops`, and `sdhci-sprd` (eMMC/microSD).
* **3D Acceleration:** Mesa `panfrost` for Mali-G52 MP2 once GPU power domains and OPP tables are wired in the board Devicetree.

### Layer 2: Cherry-Picks from `ums9230-mainline` (Codeberg)
* **USB PHY & DWC3 Glue:** Upstream bindings and PHY drivers (`drivers/phy/sprd/`) required to run the DesignWare USB3 controller in peripheral/OTG mode for Nura USB gadget networking.
* **Display Pipeline (`sprd-dpu` / `sprd-dsi`):** Extensions to the upstream Spreadtrum DRM/KMS and MIPI DSI host drivers supporting the Tiger-series display controller revision.

### Layer 3: Isolated Out-of-Tree Modules (Deferred to Phase 5)
* **Wireless (`uwe5622`):** Keep the out-of-tree Wi-Fi/Bluetooth driver (sourced from Armbian's `sprd-ums512` tree) isolated from your base kernel commits until USB SSH, storage, and display are stable.

---

## 3. Phased Bring-Up Roadmap

```
[Phase 1: Scaffolding] ──► [Phase 2: Core Boot] ──► [Phase 3: USB & Shell]
                                                            │
┌───────────────────────────────────────────────────────────┘
▼
[Phase 4: Graphics] ──► [Phase 5A: Touch & Keys] ──► [Phase 5B: Battery & Charger] ──► [Phase 5C: Wireless]
```

| Phase | Milestone | Key Technical Deliverables | Verification Gate |
| :--- | :--- | :--- | :--- |
| **1. Scaffolding** | Firmware extraction & Nura `pmaports` setup | Unpack stock `boot.img` headers/offsets; decompile stock DTB; initialise `pmbootstrap` on `edge` channel with `device-samsung-gtaba8` and `linux-samsung-gtaba8`. | `pmbootstrap` builds skeleton packages and generates valid Samsung `boot.img` headers. |
| **2. Core Boot** | Minimal DTS, `earlycon` & RAMOOPS | Create `ums512-samsung-gtaba8.dts` in `arch/arm64/boot/dts/sprd/`; configure `SC2730` PMIC nodes, memory map, and `pstore`/`ramoops` reserved RAM. | Device boots `v7.3` via Heimdall; kernel panic or boot logs persist in RAMOOPS across reboots. |
| **3. USB & Shell** | USB gadget networking & Nura initramfs | Cherry-pick `UMS512` USB PHY patches; enable `CONFIG_USB_CONFIGFS_F_RNDIS` / `CDC_ECM`; boot Nura `mkinitfs` ramdisk. | Host PC detects `usb0` (`172.16.42.1`); active SSH/telnet shell into Nura initramfs; eMMC visible under `/dev/mmcblk0`. |
| **4. Graphics** | `simplefb` console to native DRM/Panfrost | Bring up bootloader-adopted `ums512_dpu_kms` (`card0`) and `panfrost` (`card1`/`renderD128`) at `1200x1920@60Hz`; configure KWin Wayland environment. | Hardware-accelerated Wayland session (KDE Plasma Mobile) renders at native `1200x1920`. |
| **5A. Touch & Keys** *(Done)* | Multi-touch SPI & hardware buttons (`libinput`) | Port Novatek NT36523B TDDI host-download driver on `SPI2` (`0x70a00000`, `spi2.1`); load `nt36523b_qc_inx_fw.bin`; verify `sec_touchscreen` & `gpio-keys`. | 10-point multi-touch input (`event0`) and physical keys unlock and control Plasma Mobile on a Nura Edge rootfs. |
| **5B. Battery & Charger** | `SC2730` fuel gauge & USB charger | Wire `SC2730` FGU (`0x4002e000` / `sc27xx_fuel_gauge`) with SM-X200 OCV/temperature tables and I2C4 charger IC (`bq25890`/`sy6970`/`sgm4154x`) under `/sys/class/power_supply/`. | Live battery percentage, voltage, current, and charging status report accurately in `upower` / Plasma Mobile. |
| **5C. Wireless (`uwe5622`)** | Marlin3-Lite (`SC2355`) Wi-Fi & Bluetooth | Enable SDIO1 (`0x71200000`), integrate and port isolated out-of-tree `uwe5622` (`sprdwcn` / `sprdwl_ng`) Wi-Fi & BT drivers to `v7.3`, and deploy firmware. | WLAN association (`wlan0`) and Bluetooth work reliably on a Nura Edge rootfs without destabilizing core subsystems. |

---

## 4. Repository & Development Workflow

Keep the kernel source and Nura packaging decoupled across two local Git repositories to simplify rebasing and eventual upstreaming:

1. **Kernel Repository (`linux`):**
   * Branch directly from `torvalds/linux` tag `v7.3`.
   * Maintain strict commit separation: keep cherry-picked `ums9230-mainline` driver commits distinct from your board-specific `ums512-samsung-gtaba8.dts` and panel driver commits. This keeps your branch clean for eventual submission to LKML or Nura's shared `linux-postmarketos-sprd` kernel package.
2. **Nura Packaging Repository (`pmaports`):**
   * Check out the `master` branch of Nura's `pmaports` (which tracks the rolling `edge` channel).
   * Create `device/testing/device-samsung-gtaba8` (defining `deviceinfo` flash offsets, `deviceinfo_chassis="tablet"`, and `mkbootimg` parameters) and `device/testing/linux-samsung-gtaba8` (pointing `APKBUILD` to your local `v7.3` git tree and `defconfig`).

### Fast Iteration Loop
During Phases 2–4, iterate directly on `boot.img` without reflashing the rootfs:
```bash
pmbootstrap build linux-samsung-gtaba8 --force
pmbootstrap initfs
pmbootstrap flasher flash_kernel
```
* **Before USB networking works (Phase 2):** Inspect `pstore`/`ramoops` logs after rebooting into recovery or stock OS.
* **Once USB networking is active (Phase 3+):** Stream live kernel logs over SSH via `dmesg -w`.