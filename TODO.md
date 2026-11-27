# TODO

Follow-up tasks remaining after the `#14-samsung-gtaba8` clean flash and RAM/display verification (2026-11-26).
Earlier diagnostic capture: [`logs/v7_3_plasma_gpu_diag.txt`](logs/v7_3_plasma_gpu_diag.txt).

## Kernel

### GPU DVFS stuck at 384 MHz / 700 mV
- [x] Make `gpu-core-clk` actually follow Panfrost devfreq requests.
  - **What we saw:** under load, `/sys/class/devfreq/60000000.gpu/cur_freq` moves between `384000000` and `850000000`. But `gpu-core-clk` stays at `384000000`, `vddgpu` stays at `700000` µV, and `gpll-gate` stays disabled.
  - **Root cause & fix (`linux/` `9d5357e988f4`):** updated `sprd_comp_determine_rate()` in `drivers/clk/sprd/composite.c` to evaluate all mux parents via `divider_determine_rate()`, added `sprd_comp_set_rate_and_parent()`, and replaced `regmap_read`/`regmap_write` with `regmap_update_bits()` in `drivers/clk/sprd/{gate,mux,div}.c`.
  - **Verified on `#14-samsung-gtaba8` ([`logs/v7_3_kernel_todo_verify.txt`](logs/v7_3_kernel_todo_verify.txt), [`logs/v7_3_kernel_todo_dmesg.txt`](logs/v7_3_kernel_todo_dmesg.txt)):**
    - `384 MHz`: `twpll-384m` → `gpu-core-clk=384000000`, `vddgpu=700000 uV`, `45.51 fps` (`glErr=0`)
    - `512 MHz`: `twpll-512m` → `gpu-core-clk=512000000`, `vddgpu=750000 uV`, `60.84 fps` (`glErr=0`)
    - `614.4 MHz`: `lpll-614m4` → `gpu-core-clk=614400000`, `vddgpu=750000 uV`, `72.75 fps` (`glErr=0`)
    - `768 MHz`: `twpll-768m` → `gpu-core-clk=768000000`, `vddgpu=800000 uV`, `90.27 fps` (`glErr=0`)
    - `850 MHz`: `gpll-gate` enabled (`Y`), `gpll` → `gpu-core-clk=850000000`, `vddgpu=800000 uV`, `99.99 fps` (`glErr=0`, 2.20× throughput vs 384 MHz)
    - `simple_ondemand` ramps up to `850 MHz` / `800 mV` under load (`194` devfreq transitions) with `0` Panfrost faults in `dmesg`.

### Validate & commit `ums512_dpu_kms.c` and `ums512-samsung-gtaba8.dts`
- [x] Finish hardware-validating `drivers/gpu/drm/sprd/ums512_dpu_kms.c` and commit both uncommitted kernel changes cleanly.
  - **Committed in `linux/`:** `4c11f3116cbb` (`arm64: dts: sprd: ums512-samsung-gtaba8: reserve TrustZone-firewalled high-RAM regions`) and `efa35a6c4539` (`drm/sprd: ums512_dpu_kms: declare linear modifiers, index layers by plane, and drain events on disable`).
  - **Verified on `#14-samsung-gtaba8` ([`logs/v7_3_kernel_todo_verify.txt`](logs/v7_3_kernel_todo_verify.txt), [`logs/v7_3_kernel_todo_dmesg.txt`](logs/v7_3_kernel_todo_dmesg.txt)):**
    - Direct DRM atomic test on `/dev/dri/card0`: all 4 planes report immutable `zpos` `0..3` and `DRM_FORMAT_MOD_LINEAR` (`0x0`); atomic commit with primary plane `0` + overlays `2` and `3` (leaving plane `1` disabled) and 3/3 DPMS `ACTIVE` `0↔1` cycles delivered flip events cleanly without timeout.
    - Live KWin (`kwin_wayland` + `plasmashell` + `plasma-keyboard`) started cleanly with `KWIN_DRM_USE_MODIFIERS=0` removed (`modifier=0x0`, `dma_addr=0xd3d00000`), passed 2/2 `kscreen-doctor --dpms off` / `on` cycles, and recorded `0` underflows/vblank/flip errors in `dmesg`. Dropped `KWIN_DRM_USE_MODIFIERS=0` in `pmaports` (`device-samsung-gtaba8` `pkgrel=8`).

### Non-fatal `panfrost_gem_open` `WARN_ON` on PRIME dma-buf import
- [x] Fix or audit `WARNING: drivers/gpu/drm/panfrost/panfrost_gem.c:224 at panfrost_gem_open+0x1a0/0x1b8` (`WARN_ON(bo->base.madv != PANFROST_MADV_WILLNEED)`).
  - **Root cause & fix (`linux/` `ae414cec4630`):** rejects invalid madv modes and `PANFROST_MADV_DONTNEED` on PRIME-exported, PRIME-imported, or flink-named BOs in `panfrost_ioctl_madvise()`, and adds `panfrost_gem_ensure_willneed()` in `panfrost_gem_open()` and `panfrost_gem_prime_export()`.
  - **Verified on `#14-samsung-gtaba8` ([`logs/v7_3_kernel_todo_verify.txt`](logs/v7_3_kernel_todo_verify.txt), [`logs/v7_3_kernel_todo_dmesg.txt`](logs/v7_3_kernel_todo_dmesg.txt)):** launched `angelfish` with active WebGL/PRIME rendering (`3` Panfrost `renderD128` clients, shared PRIME BOs exported, shrinker purging active) with `0` `panfrost_gem_open` warnings or `WARNING`/`cut here` entries in `dmesg`.

### UMS512 Active CPUFreq / Hardware DVFS (`topdvfs` + `cpudvfs` + `fan53555`)
- [ ] Port/implement active CPU frequency and voltage scaling for `UMS512` (`sharkl5pro`) with Energy Aware Scheduling (`EAS`).
  - **Current state:** `/sys/devices/system/cpu/cpufreq/` is empty (`ums512` uses `topdvfsctrl@322a0000`, `cpudvfs-dev@322a8000`, `aon_i2c0@32060000`, external `fan53555@60` for big A75 rail, `SC2730` ADI HW channels, and eFuse binning; UMS9230's SIP SMC `sprd-cpufreq-v2` does not apply). Deep sleep (`SYSTEM_SUSPEND`) and CPUIdle (`LIT_CORE_PD` / `BIG_CORE_PD` + `teo`) already power down idle cores.

## Tablet userspace

### `ActionDrawer.qml` & `QuickSettings.qml` QML TypeErrors on Qt 6.12
- [ ] Track/fix upstream `plasma-mobile-6.8.3-r0` QML errors on `qt6-qtdeclarative-6.12.0-r2`.
  - **Current state on clean flash:** the temporary on-device `.orig` QML workarounds were wiped by the clean install, and `plasmashell --no-respawn` now stays running cleanly once RAM is uncorrupted, but `journalctl` still logs:
    - `qrc:/org/kde/plasma/private/mobileshell/ActionDrawer.qml:101: TypeError: Cannot read property 'Landscape' of undefined`
    - `qrc:/org/kde/plasma/private/mobileshell/actiondrawer/private/QuickSettings.qml:102-104: TypeError: Cannot read property 'text'/'status'/'icon' of undefined`
  - Consider reporting upstream (`ActionDrawer.qml:101` self-reference when width ÷ scale `1200 / 1.65 = 727` exceeds `largePortraitThreshold`, and unguarded `modelData` / `width == 0` bindings in `QuickSettings.qml`) or verifying once Alpine Edge updates `plasma-mobile`.

### KWin `udmabuf` warnings
- [ ] Investigate repeated `kwin_core: Could not create udmabuf: Invalid argument` messages in `journalctl`.
  - **Where to look:** `CONFIG_UDMABUF` kernel settings / limits (`size_limit_mb`) and why KWin's `/dev/udmabuf` (`llvmpipe`) render device path is attempting invalid allocations alongside Panfrost.
