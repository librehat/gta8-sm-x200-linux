# Wi-Fi (`UWE5622` / `SC2355` Marlin3-Lite)

## Hardware & DTS

- **SoC / Combo Module**: Unisoc `UWE5622` / Marlin3-Lite (`SC2355` AB, hardware chip ID `0x2355b001`, firmware `MARLIN3_20A_W24.24.2`) — a Wi-Fi/Bluetooth/GNSS combo chip (Wi-Fi and Bluetooth are working; GNSS is not enabled/tested).
- **Bus**: `&sdio1` (`0x71200000`, alias `mmc2`), 4-bit UHS-I `SDR104` at `208 MHz` (`sprd,phy-delay-sd-uhs-sdr104`, `sprd,phy-delay-sd-uhs-sdr50`, `keep-power-in-suspend`, `non-removable`, `no-sd`, `no-mmc`).
- **DTS Control Node (`sprd-marlin3`)** & Wi-Fi Platform (`sprd-wlan`, `"sprd,sc2355-wifi"`):
  - Rails: `avdd12-supply = <&vddwcn>`, `avdd33-supply = <&vddwifipa>`, `dcxo18-supply = <&vddsim2>`, `rfcustom-supply = <&vddkpled>`
  - Clocks: `aon_clk CLK_AUX0` (`32k` aux clock), `ext_32k`, `aonapb_gate CLK_AUX0_EB`, `xtal-26m-clk-type = "TSX"`
  - GPIOs: `enable-gpios` (`ap_gpio 143`), `reset-gpios` (`ap_gpio 95`), `m2-to-ap-irq-gpios` (`ap_gpio 94`), `m2-wakeup-ap-gpios` (`ap_gpio 32`), `permit-ap-send-gpios` (`ap_gpio 121`), `m2-to-ap-coexist-gpios` (`ap_gpio 119`)
  - SDIO mode flags: `blksz-512` (external GPIO RX IRQ via `m2-wakeup-ap-gpios`, no `data-irq`, no `adma-tx`/`adma-rx`)
- **Drivers**: Out-of-tree isolated modules sourced from Armbian's `sprd-ums512` tree under `linux/drivers/net/wireless/uwe5622/` (`uwe5622_bsp_sdio.ko` + `sprdwl_ng.ko`), creating `wlan0` and `p2p-dev-wlan0`.
- **Firmware**: Extracted from the stock Samsung `wcnmodem` partition / `/vendor/etc/wifi` via `tools/extract-firmware.sh --pull-wireless` and packaged in `firmware-samsung-gta8`:
  - `/usr/lib/firmware/uwe5622/wcnmodem.bin`
  - `/usr/lib/firmware/uwe5622/wifi_board_config.ini`

## Quirks & Engineering Fixes Required

### 1. Raw Partition `wcnmodem.bin` `SignerVer` Footer Clamping (`55bfb66efe70`)
- Dumping `wcnmodem` directly from eMMC yields a raw `10 MiB` (`0xa00000`) image with a `SignerVer` footer at `0xe73b0` instead of a trimmed APK/vendor file.
- `wcn_boot.c` clamps the download size at the `SignerVer` footer (`0xe73b0`) rather than attempting to push `10 MiB` over SDIO into CP2 IRAM (`CP_START_ADDR=0x001a0aa0`).

### 2. `sdio1` Non-Removable Rescan & `arm64` Stack Guard (`d5abf6c28308`, `e9f716a6219d`, `b5ffe420e857`)
- `&sdio1` is marked `non-removable`; `sdiohal_scan_card` resets `rescan_entered` so the host rescans once Marlin3 is powered on and clocked.
- Removed the legacy `__stack_chk_guard` re-export (`b5ffe420e857`) that fails to build on `arm64`.

### 3. `sdhci-r11` 4-Byte / Unaligned DT CMD53 Zero-Read Bug (`71567259b932`, `9f10030ba782`)
- On the SM-X200 `sdhci-r11` controller, 4-byte (and 80-byte) Direct-Transfer (`DT`) CMD53 reads return all zeroes (`0x00000000`), breaking `chipid`, `SYNC_ADDR`, and CP2 memory reads (`4-byte` DT writes work fine).
- `sdiohal_readl()` and `sdiohal_dt_read()` were updated to use `64`-byte / `512`-byte DMA-aligned CMD53 transfers from `p_data->dt_buf` (extracting the first 32-bit word for `sdiohal_readl()`), paired with `dma_wmb()` before `SDHCI_COMMAND` in `sdhci-sprd.c` (`71567259b932`).

### 4. In-Band SDIO DAT1 IRQ Storm vs Dedicated External RX GPIO IRQ (`m2-wakeup-ap`)
- `sdhci.c` does not W1C `SDHCI_INT_CARD_INT` before re-arming `SDHCI_SIGNAL_ENABLE`, causing in-band `data-irq` / `cap-sdio-irq` on SM-X200 (`sdhci-r11`) to continuously re-trigger `mmc2` interrupts (~37.8k IRQs/sec idle) even when `SDIO_CCCR_INTx == 0x00`, pinning CPU0 and keeping `sdio1-2x` continuously clocked.
- **Fix:** Removed hardcoded `-DCONFIG_SDIO_INBAND_INT` from `unisocwcn/Makefile`, added `"m2-wakeup-ap"` (`ap_gpio 32`) lookup in `sdiohal_parse_dt()` (`sdiohal_main.c`), dropped `data-irq;` from `sprd-marlin3` and `cap-sdio-irq;` from `&sdio1` in DTS (matching stock SM-X200), updated `sdhci-sprd.c` to enable `CLK_AUTO` whenever `!(host->mmc->caps & MMC_CAP_SDIO_IRQ)`, and fixed `sdiohal_suspend()` / `pub_int` suspend ordering so RX/`pub_int` IRQs are quiesced and drained before clearing `flag_resume`.

### 5. SDMA Packet Mode vs ADMA (`f8e1959ff503`, `a76c736ef4b4`)
- Hardcoded `-DCONFIG_SDIO_TX_ADMA_MODE` / `-DCONFIG_SDIO_RX_ADMA_MODE` flags in `unisocwcn/Makefile` and `adma-tx`/`adma-rx` DTS properties caused scatter-gather ADMA descriptors to hang packet-mode CMD53 transfers (`-110` timeout).
- Removing both puts the link into `sdio_config rx mode:[sdma]` (`sdio_config:0x80831`, contiguous 512B-aligned CMD53 buffers).

### 6. Mandatory `CONFIG_MEM_PD` Handshake for Stock `wcnmodem.bin` (`633232305543`)
- Stock Samsung `wcnmodem.bin` asserts `PUB_INT_STS0=0x1` (`MEM_SAVE_BIN`) right after calibration sync (`0xf0f0f0ff`) and enters a `while(1)` loop waiting for the AP to save CP2's BT (`0x405a8000..0x405de200`, `0x36200` B) and Wi-Fi (`0x40520000..0x40590000`, `0x70000` B) memory bins, power down their IRAM/DRAM domains, and send `SAVE_CP_MEM` to break CP2 out of `while(1)` and launch `sdiom_thread` + Wi-Fi/BT tasks.
- Without `-DCONFIG_MEM_PD` in `unisocwcn/Makefile`, every subsequent packet-mode command (`get_cp2_version`, `switch_cp2_log`, `WIFI_CMD_SYNC_VERSION`) timed out (`-110`).
- **Spinlock Over-Read Guard**: Because `sdiohal_readl()` performs a 64-byte read (`16 × u32`), reading a hardware spinlock status register in `0x40850800..0x408508fc` during `mem_pd_spinlock_lock()` also reads the next 15 spinlock slots. `sdiohal_readl()` now immediately writes `0x55AA10C5` (`UNLOCK_TOKEN`) to any trailing slots in that range that returned `0` (acquired).

### 7. Direct Firmware Lookup Eliminates 60s Boot Delay (`bc17dfb208c8`)
- `CONFIG_FW_LOADER_USER_HELPER_FALLBACK=y` caused `firmware_request_nowarn()` in `rf_marlin3.c` to block for 60 seconds probing for an absent `uwe5622/wifi_2355b001_1ant.ini` before falling back to `uwe5622/wifi_board_config.ini`.
- Switching both `rf_marlin3.c` and `wcn_boot.c` initial lookups to `request_firmware_direct()` reduced `wlan0` registration time from `~68.6s` to `~7.6s` (`28 ms` after CP2 boot).
