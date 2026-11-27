# AGENTS.md — Google Antigravity Workspace Instructions

## 1. Project Identity & Mission

You are an autonomous embedded Linux and kernel engineering agent working on porting **Nura Edge** (formerly postmarketOS) to the **Samsung Galaxy Tab A8 10.5 (2021)** (`SM-X200` Wi-Fi / `SM-X205` LTE, SoC: Unisoc Tiger T618 / `UMS512` / `sharkl5pro`).

- **Documentation & Source of Truth:** Consult [`docs/README.md`](docs/README.md) (per-subsystem hardware notes, drivers, and quirks), [`DEVELOPMENT.md`](DEVELOPMENT.md) (host setup, repo layout, and build/flash workflow), and [`TODO.md`](TODO.md) (active follow-up tasks) before starting any task.
- **Target Kernel Baseline:** Mainline Linux **`v7.3` LTS** (`torvalds/linux` tag `v7.3`) plus targeted peripheral cherry-picks from Otto Pflüger's `ums9230-mainline` staging tree.

---

## 2. Workspace Layout & Domain Boundaries

Keep concerns strictly separated across directories to prevent merge conflicts and maintain upstreamable Git history:

| Path | Purpose | Agent Permissions |
| :--- | :--- | :--- |
| `README.md` | Project description | Read-only reference (update status notes only on request) |
| `AGENTS.md` | Root agent instructions and guardrails | Read-only unless explicitly asked to update |
| `DEVELOPMENT.md` | Host setup, repo workflow, build and flashing guide | Read-only reference (update only on request) |
| `docs/` | Per-subsystem hardware support, architecture, and driver quirk notes | Update when subsystem behaviour or quirks change |
| `TODO.md` | Active follow-up kernel and userspace tasks | Update when tasks are added or verified |
| `firmware/` | Stock Samsung `boot.img`, decompiled downstream `.dts`, and `hardware_map.txt` | Write extracted artifacts here; never modify raw stock binaries |
| `linux/` | Kernel tree branched from `v7.3` (`arch/arm64/boot/dts/sprd/`) | Full read/write within assigned task scope |
| `pmaports/` | Nura Edge packaging (`device/testing/device-samsung-gta8`, `linux-samsung-gta8`, `firmware-samsung-gta8`) | Full read/write within assigned task scope |
| `tools/` | Firmware extraction, `dtbo-noop`, `reloc.S`, build/flash, and USB networking helper scripts | Read/write within assigned task scope |
| `logs/` | Captured `ramoops`/`pstore` dumps, serial logs, and `dmesg` outputs | Append/write diagnostic logs for root-cause analysis |

---

## 3. Architectural & Coding Guardrails (CRITICAL)

1. **No Downstream 4.14 Hacks:** Never port legacy Android 4.14 kernel workarounds (e.g., `CONFIG_ANDROID_PARANOID_NETWORK`, proprietary Mali `midgard` blobs, or vendor binder/ashmem shims). Target clean mainline interfaces (`panfrost`, `CONFIGFS` USB gadgets, `simpledrm`/`ums512_dpu_kms`).
2. **Use Mainline `sprd` Naming:** Upstream Linux places Unisoc architecture code under `sprd` (`arch/arm64/boot/dts/sprd/`, `drivers/clk/sprd/`, `drivers/pinctrl/sprd/`, `drivers/mmc/host/sdhci-sprd.c`), **not** `unisoc`. Follow upstream naming conventions for all new DTS files (e.g., `ums512-samsung-gta8.dts`).
3. **Leverage Native `v7.3` `SC2730` Support:** The Unisoc `SC2730` PMIC regulator driver (`CONFIG_REGULATOR_SC2730`) is mainline in `v7.3`. Do not apply out-of-tree PMIC regulator patches.
4. **Strict Git Commit Hygiene:**
   - Keep cherry-picked commits from `ums9230-mainline` (USB PHY, clock/SDHCI/SPI/I2C fixes) isolated from board-specific `ums512-samsung-gta8.dts` and DRM/touch driver commits.
   - Write clear, subsystem-prefixed commit messages (e.g., `arm64: dts: sprd: Add initial Samsung Galaxy Tab A8 (SM-X200) board`).
5. **Keep Out-of-Tree Wireless (`uwe5622`) Isolated:** Keep out-of-tree `drivers/net/wireless/uwe5622/` commits isolated from mainline and board commits, and avoid changes that destabilize core subsystems.

---

## 4. Standard Build & Verification Commands

Use these commands inside the Linux sandbox to validate changes before requesting hardware testing:

- **Kernel & DTB Cross-Compilation (`linux/`):**
  ```bash
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image sprd/ums512-samsung-gta8.dtb
  ```
- **Device Tree Syntax & Binding Validation (`linux/`):**
  ```bash
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CHECK_DTBS=y sprd/ums512-samsung-gta8.dtb
  ```
- **Nura Edge Package & Initramfs Build (`pmaports/` or repo root):**
  ```bash
  ./tools/flash-gta8.sh build-kernel
  # Or manually:
  pmbootstrap checksum device-samsung-gta8 linux-samsung-gta8
  pmbootstrap build firmware-samsung-gta8 --src="$PWD/firmware" --force
  pmbootstrap build device-samsung-gta8 --force
  pmbootstrap build linux-samsung-gta8 --src="$PWD/linux" --force
  pmbootstrap initfs
  ```

---

## 5. Agentic Workflow & Human Checkpoints

### Autonomous Execution Loop
1. **Plan:** Read the relevant subsystem notes in `docs/`, workflow in `DEVELOPMENT.md`, and open tasks in `TODO.md`, then generate an implementation plan detailing the exact files, Kconfig symbols, and DTS nodes to create or modify.
2. **Execute:** Implement changes in small, atomic steps. When spawning parallel subagents, isolate them strictly by workspace domain (e.g., Subagent A updates kernel DTS/drivers while Subagent B updates `pmaports/device/testing/*gta8*`).
3. **Verify Locally:** Compile the kernel, DTB, and `pmbootstrap` packages. Resolve all compiler or `dtc` errors/warnings autonomously before concluding a turn.

### Mandatory Human-in-the-Loop Checkpoints
**NEVER** attempt to flash physical hardware (`heimdall flash`, `pmbootstrap flasher`, `./tools/flash-gta8.sh flash*`) autonomously. Whenever a workflow reaches a hardware test step:
1. Pause execution and summarize the built artifacts (e.g., `boot.img`, DTB, initramfs).
2. Provide the exact flashing and host-side diagnostic commands for the user to run (e.g., `./tools/flash-gta8.sh flash-kernel`, `./tools/usbnet-up.sh`, `ssh user@172.16.42.1` for rootfs or `ssh root@172.16.42.1` in initramfs).
3. Ask the user to paste back `ramoops` logs, `dmesg` output, or `lsusb`/`ip link` results into `logs/` so you can diagnose failures or advance.