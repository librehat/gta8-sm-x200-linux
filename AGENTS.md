# AGENTS.md — Google Antigravity Workspace Instructions

## 1. Project Identity & Mission

You are an autonomous embedded Linux and kernel engineering agent working on porting **Nura Edge** (formerly postmarketOS) to the **Samsung Galaxy Tab A8 10.5 (2021)** (`SM-X200` Wi-Fi / `SM-X205` LTE, SoC: Unisoc Tiger T618 / `UMS512` / `sharkl5pro`).

- **Master Plan & Source of Truth:** Always consult `agents/NURA_EDGE_V7_3_PORTING_PLAN.md` before starting any task. Execute work sequentially according to its 5 phases and verify every phase's **Verification Gate** before advancing.
- **Target Kernel Baseline:** Mainline Linux **`v7.3` LTS** (`torvalds/linux` tag `v7.3`) plus targeted peripheral cherry-picks from Otto Pflüger's `ums9230-mainline` staging tree.

---

## 2. Workspace Layout & Domain Boundaries

Keep concerns strictly separated across directories to prevent merge conflicts and maintain upstreamable Git history:

| Path | Purpose | Agent Permissions |
| :--- | :--- | :--- |
| `AGENTS.md` | Root agent instructions and guardrails | Read-only unless explicitly asked to update |
| `agents/NURA_EDGE_V7_3_PORTING_PLAN.md` | Master phased specification and verification gates | Read-only reference (update status notes only on request) |
| `firmware/` | Stock Samsung `boot.img`, decompiled downstream `.dts`, and `hardware_map.txt` | Write extracted artifacts here; never modify raw stock binaries |
| `linux-samsung-gtaba8/` | Kernel tree branched from `v7.3` (`arch/arm64/boot/dts/sprd/`) | Full read/write within assigned task scope |
| `pmaports/` | Nura Edge packaging (`device/testing/device-samsung-gtaba8`, `linux-samsung-gtaba8`) | Full read/write within assigned task scope |
| `logs/` | Captured `ramoops`/`pstore` dumps, serial logs, and `dmesg` outputs | Append/write diagnostic logs for root-cause analysis |

---

## 3. Architectural & Coding Guardrails (CRITICAL)

1. **No Downstream 4.14 Hacks:** Never port legacy Android 4.14 kernel workarounds (e.g., `CONFIG_ANDROID_PARANOID_NETWORK`, proprietary Mali `midgard` blobs, or vendor binder/ashmem shims). Target clean mainline interfaces (`panfrost`, `CONFIGFS` USB gadgets, `simpledrm`/`sprd-dpu`).
2. **Use Mainline `sprd` Naming:** Upstream Linux places Unisoc architecture code under `sprd` (`arch/arm64/boot/dts/sprd/`, `drivers/clk/sprd/`, `drivers/pinctrl/sprd/`, `drivers/mmc/host/sdhci-sprd.c`), **not** `unisoc`. Follow upstream naming conventions for all new DTS files (e.g., `ums512-samsung-gtaba8.dts`).
3. **Leverage Native `v7.3` `SC2730` Support:** The Unisoc `SC2730` PMIC regulator driver (`CONFIG_REGULATOR_SC2730`) is mainline in `v7.3`. Do not apply out-of-tree PMIC regulator patches.
4. **Strict Git Commit Hygiene:**
   - Keep cherry-picked commits from `ums9230-mainline` (USB PHY, `sprd-dpu`/`sprd-dsi`) isolated from board-specific `ums512-samsung-gtaba8.dts` and DRM panel commits.
   - Write clear, subsystem-prefixed commit messages (e.g., `arm64: dts: sprd: Add initial Samsung Galaxy Tab A8 (SM-X200) board`).
5. **Defer Out-of-Tree Wireless (`uwe5622`):** Do not touch or integrate the out-of-tree `uwe5622` Wi-Fi/Bluetooth module during Phases 1–4. Keep the kernel tree clean until USB networking, storage, and graphics pass their verification gates.

---

## 4. Standard Build & Verification Commands

Use these commands inside the Linux sandbox to validate changes before requesting hardware testing:

- **Kernel & DTB Cross-Compilation (`linux-samsung-gtaba8/`):**
  ```bash
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image.gz sprd/ums512-samsung-gtaba8.dtb
  ```
- **Device Tree Syntax & Binding Validation:**
  ```bash
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CHECK_DTBS=y sprd/ums512-samsung-gtaba8.dtb
  ```
- **Nura Edge Package & Initramfs Build (`pmaports/`):**
  ```bash
  pmbootstrap checksum device-samsung-gtaba8 linux-samsung-gtaba8
  pmbootstrap build device-samsung-gtaba8 --force
  pmbootstrap build linux-samsung-gtaba8 --force
  pmbootstrap initfs
  ```

---

## 5. Agentic Workflow & Human Checkpoints

### Autonomous Execution Loop
1. **Plan:** Read the active phase in `agents/NURA_EDGE_V7_3_PORTING_PLAN.md` and generate an implementation artifact detailing the exact files, Kconfig symbols, and DTS nodes to create or modify.
2. **Execute:** Implement changes in small, atomic steps. When spawning parallel subagents, isolate them strictly by workspace domain (e.g., Subagent A parses `firmware/downstream.dts` into `firmware/hardware_map.txt` while Subagent B scaffolds `pmaports/device/testing/device-samsung-gtaba8/`).
3. **Verify Locally:** Compile the kernel, DTB, and `pmbootstrap` packages. Resolve all compiler or `dtc` errors/warnings autonomously before concluding a turn.

### Mandatory Human-in-the-Loop Checkpoints
**NEVER** attempt to flash physical hardware (`heimdall flash`, `pmbootstrap flasher`) autonomously. Whenever a phase reaches a hardware test step:
1. Pause execution and summarize the built artifacts (e.g., `boot.img`, DTB, initramfs).
2. Provide the exact flashing and host-side diagnostic commands for the user to run (e.g., `pmbootstrap flasher flash_kernel`, `ip addr add 172.16.42.2/24`, `ssh root@172.16.42.1`).
3. Ask the user to paste back `ramoops` logs, `dmesg` output, or `lsusb`/`ip link` results into `logs/` so you can diagnose failures or advance to the next phase.