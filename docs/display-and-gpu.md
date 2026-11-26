# Display & GPU

## Display (`ums512_dpu_kms`) — Working

### Hardware & Architecture
- **Panel / Mode**: `1200x1920` (`width-mm = <136>`, `height-mm = <225>`, `x8r8g8b8`, bootloader MIPI-DSI video mode initialized by LK at `0x9e000000`, `0x009e4000` B).
- **Driver**: Native UMS512 DPU r4p0 KMS driver (`display@20300000`, compatible `"sprd,ums512-dpu-kms"`, `db9560224249`), with `DRM_FORMAT_MOD_LINEAR` support, deterministic `plane->index` hardware layer assignment, and IRQ/event draining on CRTC disable for DPMS blank/unblank cycles (`efa35a6c4539`).
- **DT Handoff Setup** (`be4c7bd27738`):
  - `framebuffer@9e000000` is marked `status = "disabled"` in `chosen` so `simpledrm` does not bind; `ums512-dpu-kms` reads `sprd,boot-framebuffer = <&framebuffer0>`.
  - Stock upstream nodes `&disp`, `&dpu`, `&iommu_disp`, and `&dsi` are disabled so `ums512-dpu-kms` exclusively owns the DPU r4p0 registers, VAU IOMMU, VSYNC/page-flip IRQs (`GIC_SPI 27`), and 4-plane scanout over CMA (`cma=256M`).

### Display Quirks
- **Panel-Vendor Agnostic**: Adopts LK's pre-initialized MIPI-DSI video link rather than re-initializing DSI from scratch, working across SM-X200 panel variants (`novatek-nt36523` panel driver `71b301f00f28` also present for reference).
- **No KWin Environment Overrides**: KWin auto-discovers the display via udev — `card0` (`ums512-dpu`) passes `drmIsKMS()` while `card1` (render-only `panfrost`) is skipped — and pairs it with Panfrost `renderD128` as the primary render GPU. Neither `KWIN_DRM_DEVICES` nor `KWIN_FORCE_SW_CURSOR` is needed (the DPU exposes no cursor plane, and KWin does not use overlay planes on non-Intel KMS by default).
- **Clock/Power Domain Retention**: Boot cmdline includes `clk_ignore_unused pd_ignore_unused` so display clocks/domains set up by LK stay alive across probe.

---

## GPU (Mali-G52 MP2 Bifrost / `panfrost`) — Working

### Hardware & Drivers
- **DTS**: `&gpu` (`status = "okay"`, `mali-supply = <&vddgpu>`, compatible `"sprd,ums512-mali"`, `b1a6e1947ff9`, `c3c2d937ec41`).
- **Dependencies**:
  - `pmdomain-sprd` (`b0cb56cab9f6`) for UMS512 GPU power domain control.
  - `clk-sprd` reparenting & composite clock DVFS (`6a7f68b897a1`, `9d5357e988f4`): `sprd_comp_determine_rate()` evaluates all candidate mux parents, `sprd_comp_set_rate_and_parent()` sequences divider/mux updates safely, and `gate.c`/`mux.c`/`div.c` use `regmap_update_bits()` to serialize concurrent CCF updates to shared control registers (such as `0x60100004` shared by `gpu-core-gate` and `gpu-core-clk`).
  - Panfrost UMS512/UMS9230 clock-gating, stability, and PRIME `madvise` fixes (`dc0d9dba23c1`, `5f992a01a5ad`, `55d24195778b`, `832541166fce`, `c7d5fcf6b100`, `de6f60c022aa`, `ae414cec4630`).

### GPU Quirks & Bring-Up Fixes
- **DVFS Scaling (384–850 MHz / 700–800 mV)** (`9d5357e988f4`): Panfrost `devfreq` (`simple_ondemand`) scales `gpu-core-clk` and `vddgpu` across all five UMS512 OPPs (`384 MHz` via `twpll-384m` @ `700 mV`, `512 MHz` via `twpll-512m` @ `750 mV`, `614.4 MHz` via `lpll-614m4` @ `750 mV`, `768 MHz` via `twpll-768m` @ `800 mV`, and `850 MHz` via `gpll-gate`/`gpll` @ `800 mV`, verified at 2.20× GLES2 throughput at 850 MHz vs 384 MHz).
- **TrustZone-Firewalled High-RAM Carveouts** (`4c11f3116cbb`): Earlier Panfrost page faults and compositor crashes under load were traced to buddy/CMA allocations landing in unreserved TrustZone-firewalled high DDR (`0xe32ae000..0xfffa0000`); reserving `drm-mem`, `faceid-mem`, `vdsp-mem`, `framebuffer-mem`, and `writeback-mem` as `no-map` eliminated memory/GPU corruption (see [`boot.md`](boot.md)).
- **PRIME `dma-buf` `madvise` Handling** (`ae414cec4630`): `panfrost_ioctl_madvise()` rejects `PANFROST_MADV_DONTNEED` on PRIME-exported/imported or flink-named BOs, and `panfrost_gem_ensure_willneed()` resets shared BOs on `panfrost_gem_open()` and `panfrost_gem_prime_export()`, preventing the `WARN_ON(bo->base.madv != PANFROST_MADV_WILLNEED)` trace during multi-client WebGL (`angelfish`) rendering.
