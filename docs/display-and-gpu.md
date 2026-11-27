# Display & GPU

## Display (`ums512_dpu_kms`) — Working

### Hardware & Architecture
- **Panel / Mode**: `1200x1920@60Hz` (`width-mm = <136>`, `height-mm = <225>`, `rotation = <90>`, `x8r8g8b8`, bootloader MIPI-DSI video mode initialized by LK at `0x9e000000`, `0x009e4000` B).
- **Driver**: Native UMS512 DPU r4p0 KMS driver (`display@20300000`, compatible `"sprd,ums512-dpu-kms"`, `db9560224249`), with `DRM_FORMAT_MOD_LINEAR` support, deterministic `plane->index` hardware layer assignment, IRQ/event draining on CRTC disable (`efa35a6c4539`), DT panel orientation parsing via `drm_of_get_panel_orientation()` / `drm_connector_set_panel_orientation()`, MIPI-DSI DCS backlight (`ums512-dpu-backlight` via DSI host `0x20400000`), panel sleep-in/sleep-out (`panel_sleep`), and `drm_mode_config_helper_suspend`/`resume` PM ops.
- **DT Handoff Setup** (`be4c7bd27738`):
  - `framebuffer@9e000000` is marked `status = "disabled"` in `chosen` so `simpledrm` does not bind; `ums512-dpu-kms` reads `sprd,boot-framebuffer = <&framebuffer0>`.
  - Stock upstream nodes `&disp`, `&dpu`, `&iommu_disp`, and `&dsi` are disabled so `ums512-dpu-kms` exclusively owns the DPU r4p0 registers, VAU IOMMU, optional DSI LP command TX range (`0x20400000`), VSYNC/page-flip IRQs (`GIC_SPI 27`), and 4-plane scanout over CMA (`cma=256M`).

### Display Quirks
- **Panel-Vendor Agnostic**: Adopts LK's pre-initialized MIPI-DSI video link rather than re-initializing DSI from scratch, working across SM-X200 panel variants (`novatek-nt36523` panel driver `71b301f00f28` also present for reference). Backlight and panel sleep auto-detect `nt36523b`, `hx83102e`, or `ft8201ab` from the bootloader's `lcd_name=` kernel cmdline argument and transmit DCS commands in LP mode during video blanking without resetting D-PHY or touching `SOFT_RESET`.
- **DPMS Off vs System Suspend**: `dpu_crtc_atomic_disable()` forces the panel backlight (`0x51`) to `0` and blanks all DPU layers while keeping the display glass awake so `NT36523B` TDDI touch SRAM is preserved. System suspend (`dpu_pm_suspend()`) additionally sends MIPI-DCS `0x28` (Display Off) and `0x10` (Sleep In) after atomic disable (controllable via `panel_sleep=1/0`), saving ~95 mA beyond `brightness=0` (`-113 mA` -> `-14 mA`). Because `0x10` Sleep-In re-locks the `NT36523B` command gate, `dpu_panel_sleep_out_locked()` sends `nt36523b_cmd_unlock_cmds` (`0x23`: `FF 10, F0 AA, F1 55, F2 99`) before `0x11` (120 ms) + `0x29` (20 ms) + re-lock on resume.
- **Default Landscape Orientation & 150% Scaling**: `display@20300000` sets `rotation = <90>;`, which `drm_of_get_panel_orientation()` maps to DRM `"panel orientation"` = `"Right Side Up"` (`DRM_MODE_PANEL_ORIENTATION_RIGHT_UP`), rotating `fbcon` (`FB_ROTATE_CW`), Plymouth, and Wayland compositors 90° clockwise into `1920x1200` landscape. `device-samsung-gta8-kwin` also installs `/etc/xdg/kwinoutputconfig.json` with `scale: 1.5` (150% / `1280x800` logical) and `transform: "Rotated270"` for `DSI-1` as KWin's default first-boot configuration (overridable per-user in `~/.config/kwinoutputconfig.json`), while still requiring no `KWIN_*` environment overrides: KWin auto-discovers `card0` (`ums512-dpu`) via udev (`drmIsKMS()`), skips render-only `card1` (`panfrost`), and pairs it with Panfrost `renderD128` as the primary render GPU. Neither `KWIN_DRM_DEVICES` nor `KWIN_FORCE_SW_CURSOR` is needed (the DPU exposes no cursor plane, and KWin does not use overlay planes on non-Intel KMS by default).
- **Clock/Power Domain Retention**: Boot cmdline includes `clk_ignore_unused pd_ignore_unused` so display clocks/domains set up by LK stay alive across probe.

---

## GPU (Mali-G52 MP2 Bifrost / `panfrost`) — Working

### Hardware & Drivers
- **DTS**: `&gpu` (`status = "okay"`, `mali-supply = <&vddgpu>`, compatible `"sprd,ums512-mali"`, `b1a6e1947ff9`, `c3c2d937ec41`) using Mesa `panfrost` (`CONFIG_DRM_PANFROST`).
- **Dependencies**:
  - `pmdomain-sprd` (`b0cb56cab9f6`) and `ums512-clk` runtime PM (`devm_pm_runtime_enable` + `sprd_clk_pm_ops` on `gpu_clk`, `mm_clk`, `mm_gate`): `mm` (`62100000`/`62200000`) gates to `off-0` when unused, while `gpu_top` remains powered across runtime idle to avoid `sprd_pmu`'s 50 ms power-on/off latency and preserve `gpu_clk` mux/divider registers (with Panfrost `GPU_PM_RT` internally powering down Mali cores and clock-gating `gpu-*-gate` when idle).
  - `clk-sprd` reparenting & composite clock DVFS (`6a7f68b897a1`, `9d5357e988f4`): `sprd_comp_determine_rate()` evaluates all candidate mux parents, `sprd_comp_set_rate_and_parent()` sequences divider/mux updates safely, and `gate.c`/`mux.c`/`div.c` use `regmap_update_bits()` to serialize concurrent CCF updates to shared control registers (such as `0x60100004` shared by `gpu-core-gate` and `gpu-core-clk`).
  - Panfrost UMS512/UMS9230 clock-gating, stability, and PRIME `madvise` fixes (`dc0d9dba23c1`, `5f992a01a5ad`, `55d24195778b`, `832541166fce`, `c7d5fcf6b100`, `de6f60c022aa`, `ae414cec4630`).

### GPU Quirks & Bring-Up Fixes
- **DVFS Scaling (384–850 MHz / 700–800 mV)** (`9d5357e988f4`): Panfrost `devfreq` (`simple_ondemand`) scales `gpu-core-clk` and `vddgpu` across all five UMS512 OPPs (`384 MHz` via `twpll-384m` @ `700 mV`, `512 MHz` via `twpll-512m` @ `750 mV`, `614.4 MHz` via `lpll-614m4` @ `750 mV`, `768 MHz` via `twpll-768m` @ `800 mV`, and `850 MHz` via `gpll-gate`/`gpll` @ `800 mV`, verified at 2.20× GLES2 throughput at 850 MHz vs 384 MHz).
- **TrustZone-Firewalled High-RAM Carveouts** (`4c11f3116cbb`): Earlier Panfrost page faults and compositor crashes under load were traced to buddy/CMA allocations landing in unreserved TrustZone-firewalled high DDR (`0xe32ae000..0xfffa0000`); reserving `drm-mem`, `faceid-mem`, `vdsp-mem`, `framebuffer-mem`, and `writeback-mem` as `no-map` eliminated memory/GPU corruption (see [`boot.md`](boot.md)).
- **PRIME `dma-buf` `madvise` Handling** (`ae414cec4630`): `panfrost_ioctl_madvise()` rejects `PANFROST_MADV_DONTNEED` on PRIME-exported/imported or flink-named BOs, and `panfrost_gem_ensure_willneed()` resets shared BOs on `panfrost_gem_open()` and `panfrost_gem_prime_export()`, preventing the `WARN_ON(bo->base.madv != PANFROST_MADV_WILLNEED)` trace during multi-client WebGL (`angelfish`) rendering.
