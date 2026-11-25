# Display & GPU

## Display (`ums512_dpu_kms`) — Working

### Hardware & Architecture
- **Panel / Mode**: `1200x1920` (`width-mm = <136>`, `height-mm = <225>`, `x8r8g8b8`, bootloader MIPI-DSI video mode initialized by LK at `0x9e000000`, `0x009e4000` B).
- **Driver**: Native UMS512 DPU r4p0 KMS driver (`display@20300000`, compatible `"sprd,ums512-dpu-kms"`, `db9560224249`).
- **DT Handoff Setup** (`be4c7bd27738`):
  - `framebuffer@9e000000` is marked `status = "disabled"` in `chosen` so `simpledrm` does not bind; `ums512-dpu-kms` reads `sprd,boot-framebuffer = <&framebuffer0>`.
  - Stock upstream nodes `&disp`, `&dpu`, `&iommu_disp`, and `&dsi` are disabled so `ums512-dpu-kms` exclusively owns the DPU r4p0 registers, VAU IOMMU, VSYNC/page-flip IRQs (`GIC_SPI 27`), and 4-plane scanout over CMA (`cma=256M`).

### Display Quirks
- **Panel-Vendor Agnostic**: Adopts LK's pre-initialized MIPI-DSI video link rather than re-initializing DSI from scratch, working across SM-X200 panel variants (`novatek-nt36523` panel driver `71b301f00f28` also present for reference).
- **No `pmaports`/KWin Modifiers or HW Cursor** (`294b091cf`):
  - [`50-samsung-gtaba8-kwin.conf`](../pmaports/device/testing/device-samsung-gtaba8/50-samsung-gtaba8-kwin.conf) and [`kwin.sh`](../pmaports/device/testing/device-samsung-gtaba8/kwin.sh) set:
    - `KWIN_DRM_DEVICES=/dev/dri/card0`
    - `KWIN_FORCE_SW_CURSOR=1`
    - `KWIN_DRM_USE_MODIFIERS=0`
- **Clock/Power Domain Retention**: Boot cmdline includes `clk_ignore_unused pd_ignore_unused` so display clocks/domains set up by LK stay alive across probe.

---

## GPU (Mali-G52 MP2 Bifrost / `panfrost`) — Partial (Unstable)

### Hardware & Drivers
- **DTS**: `&gpu` (`status = "okay"`, `mali-supply = <&vddgpu>`, compatible `"sprd,ums512-mali"`, `b1a6e1947ff9`, `c3c2d937ec41`).
- **Dependencies**:
  - `pmdomain-sprd` (`b0cb56cab9f6`) for UMS512 GPU power domain control.
  - `clk-sprd` reparenting (`6a7f68b897a1`) to reparent GPU/display gate clocks onto functional parent clocks.
  - Panfrost UMS512/UMS9230 clock-gating and stability patches (`dc0d9dba23c1`, `5f992a01a5ad`, `55d24195778b`, `832541166fce`, `c7d5fcf6b100`, `de6f60c022aa`).

### Known Limitation
- Mesa `panfrost` + `vddgpu` probes and renders `/dev/dri/card1` / `renderD128`, but stability under sustained GPU load / runtime PM remains incomplete (`Partial (unstable)`).
