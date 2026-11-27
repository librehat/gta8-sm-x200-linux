# Touchscreen & Physical Buttons

## Novatek `NT36523B` TDDI Touchscreen — Working

### Hardware & DTS
- **Bus**: `&spi2` (`0x70a00000`, chip-select `1`, `spi-max-frequency = <9600000>`).
- **DTS Node**: [`ums512-samsung-gtaba8.dts`](../linux/arch/arm64/boot/dts/sprd/ums512-samsung-gtaba8.dts#L344-L361) (`touchscreen@1`, compatible `"novatek,NVT-ts-spi-a8"`):
  - Resolution: `1200x1920`, up to `10` touch points
  - `novatek,swrst-n8-addr = <0x0003f0fe>`, `novatek,spi-rd-fast-addr = <0x0003f310>`
  - `novatek,reset-gpio = <&ap_gpio 145 GPIO_ACTIVE_HIGH>`
  - `novatek,irq-gpio = <&eic_async 0 IRQ_TYPE_EDGE_RISING>` (`IRQ 20`, `sprd-eic 0 Edge NVT-ts`)
  - `novatek,fw_name = "nt36523b_qc_inx_fw.bin"`
- **Driver**: Host-download SPI driver `nt36xxx` (`8bced3b688eb`), registering evdev/`libinput` input device `sec_touchscreen`.

### Quirks & Fixes
1. **`spi-sprd` Full-Duplex & Zero Word-Delay Fixes** (`5f549b6b332e`):
   - `spi-sprd` had bugs in full-duplex `TX+RX` transfers, zero word-delay handling, and `num_chipselect` (required for CS 1 on `spi2`), without which SPI reads from the Novatek IC fail.
2. **Volatile RAM Firmware Requires Both Initramfs & Rootfs Packaging**:
   - The `NT36523B` TDDI uses volatile SRAM host-download (`nt36523b_qc_inx_fw.bin`, `0x30000` bytes). The driver uploads firmware both when probing in initramfs and on ESD recovery after `switch_root`.
   - [`pmaports/device/testing/firmware-samsung-gtaba8/APKBUILD`](../pmaports/device/testing/firmware-samsung-gtaba8/APKBUILD#L43-L57) installs `nt36523b*.bin` into `/usr/lib/firmware/` **and** appends `/usr/lib/firmware/nt36523b_qc_inx_fw.bin` to `/usr/share/mkinitfs/files/30-initramfs-firmware-samsung-gtaba8.files` so `mkinitfs` bundles it into the initramfs (`tools/extract-firmware.sh` / `tools/flash-gta8.sh`).
3. **ESD Workqueue & Checksum Dumps** (`bcecc23f5753`):
   - Moved ESD recovery onto an unbound workqueue and ratelimited SPI packet checksum error dumps (`i2c/spi packet checksum not match`) seen around early boot / USB state transitions.
4. **PM Suspend / Resume & Wakeup Policy**:
   - `nvt_ts_pm_suspend()` calls `nvt_ts_suspend()`, which cancels ESD polling and any pending charger-notify work and masks the IRQ while skipping SPI `DSTB` (`0x11`), because `ums512_dpu_kms` never pulses display `RESX` on resume (sending `0x11` without `RESX` trapped the shared `NT36523B` TDDI die in `0xA1`/`0xFD` SPI reload storms and caused display flickering). On resume, `nvt_ts_pm_complete()` schedules a full (`full=1`) FW host-download 50 ms after DPU panel sleep-out and userspace thaw. `device_init_wakeup()` is only enabled when `aot_enable` is active (disabled by default to prevent accidental wakes in sleep).

---

## Physical Buttons (`gpio-keys`) — Working

| Key | Code | GPIO / EIC | Polarity | Wakeup |
| :--- | :--- | :--- | :--- | :--- |
| Power Key | `KEY_POWER` | `&pmic_eic 1` | `GPIO_ACTIVE_LOW` | Yes |
| Volume Up Key | `KEY_VOLUMEUP` | `&ap_gpio 125` | `GPIO_ACTIVE_LOW` | Yes |
| Volume Down Key | `KEY_VOLUMEDOWN` | `&pmic_eic 4` | `GPIO_ACTIVE_HIGH` | Yes |

- Note `Volume Down` uses `GPIO_ACTIVE_HIGH` on PMIC EIC line `4` (`debounce-interval = <2>`), whereas `Power` and `Volume Up` are active-low.
