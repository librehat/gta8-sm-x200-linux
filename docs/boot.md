# Boot, SoC Platform, Watchdog & Crash Logging

## Architecture Overview

- **Board Compatible**: `"samsung,gtaba8"`, `"sprd,ums512"` (`linux/arch/arm64/boot/dts/sprd/ums512-samsung-gtaba8.dts`).
- **SoC**: Unisoc `UMS512` (Tiger T618): 2× Cortex-A75 + 6× Cortex-A55, `4096 MiB` RAM (`memory@80000000`, size `0xfffff000`), `SC2730` PMIC over ADI + hardware spinlock (`66f55df6abc4`, `98f77b879d45`).
- **Serial Console / Earlycon**: `&uart1` (`0x70100000`, `console=ttyS1,115200n8`, `earlycon=sprd_serial,0x70100000,115200n8`), `&uart0` enabled.

## Bootloader (`LK`) & Packaging Quirks

### 1. Mandatory `dtbo-noop.img` for LK (`board_id 0x1100`)
- Even when the kernel DTB sets `sprd,sc-id = "ums512 1000 1000"`, Samsung's Little Kernel (`LK`) bootloader selects a DTBO entry by `sprd,board_id = <0x1100>` and merges it into the FDT passed to Linux.
- Merging the stock Android DTBO corrupts a mainline Device Tree. [`tools/dtbo-noop.dts`](../tools/dtbo-noop.dts) builds an empty `__overlay__` packaged into `firmware/dtbo-noop.img` (DT table + AVB hash footer for the 8 MiB `dtbo` partition) by [`tools/extract-firmware.sh`](../tools/extract-firmware.sh) and flashed with `--with-dtbo` in [`tools/flash-gta8.sh`](../tools/flash-gta8.sh).

### 2. ARM64 2 MiB Image Alignment Relocation Shim (`reloc.S`)
- Samsung's `boot.img` expects a stock-compatible `0x80000` `text_offset` in the Image header, whereas mainline `arm64` kernels expect 2 MiB physical alignment if placed arbitrarily by LK.
- [`tools/reloc.S`](../tools/reloc.S) prepends an ARM64 relocation stub (`magic = "ARMd"`, `text_offset = 0x80000`) that backward-copies the compressed payload up to the next 2 MiB boundary (`~0x1fffff`), flushes caches (`dsb sy; ic iallu; isb`), and jumps to it while preserving `x0`–`x3` (including the DTB pointer in `x0`).

### 3. AVB Hash Footer on `boot.img`
- LK verifies an Android Verified Boot hash footer on the 64 MiB (`67108864` byte) `boot` partition even with the bootloader unlocked.
- [`pmaports/device/testing/device-samsung-gtaba8/postprocess-bootimg.sh`](../pmaports/device/testing/device-samsung-gtaba8/postprocess-bootimg.sh) runs `avbtool add_hash_footer --image "$bootimgfile" --partition_name boot --partition_size 67108864 --algorithm NONE`.

### 4. Bootloader Watchdog & PMIC Reset (`SC2730`)
- LK arms the PMIC watchdog (`sc2730-wdt`, driver `sc27xx_wdt`) before jumping to the kernel. If Linux fails to pet/manage it, the tablet resets shortly after boot.
- Fix (`08384b1d7b32`, `390a7c0b1407`, `668903f648cc`): enabled `sc2730-wdt` MFD cell + `CONFIG_SC27XX_WATCHDOG` and disabled `&ap_wdt` in DTS.
- Poweroff and reboot use `sc2730-poweroff` / `sc27xx` reset (`9d8eedfc25b7`, `e4124a48ad92`, `2b844ef5c81a`).
- MFD child devices get an empty DMA mask (`8afc29f500af`) so `sc27xx` subdevices avoid spurious DMA warnings.

### 5. Kernel Command Line & Reserved Memory
- [`pmaports/device/testing/device-samsung-gtaba8/kernel-cmdline.conf`](../pmaports/device/testing/device-samsung-gtaba8/kernel-cmdline.conf) keeps `clk_ignore_unused pd_ignore_unused cma=256M` during bring-up so clocks/power domains handed off from LK (display, clocks) are not gated prematurely and `ums512_dpu_kms` has 256 MiB CMA for scanout buffers.
- `reserved-memory` (`5a48b36effe3`) mirrors the SM-X200 hardware map (`ddrbist`, `sysdumpinfo`, `rebootescrow`, `audio-mem`, `sipc-mem`, `sp-ddr-mem`, `audiodsp-mem`, `cp-modem@89600000`, `sec_debug_region@8f000000`, `sml-mem`/`tos-mem`/`sh-mem`, `framebuffer@9e000000`) plus `ramoops@fff80000` (`256 KiB` total: `32 KiB` each for `record-size`, `console-size`, `pmsg-size`) for persistent `pstore` crash logs.
