# Storage (eMMC & microSD)

## Hardware Configuration

| Controller | DTS Alias | Bus / Mode | Power Supplies | CD / Quirks |
| :--- | :--- | :--- | :--- | :--- |
| `&sdio3` | `mmc0` | 8-bit internal eMMC (`HS400ES`, `HS400`, `HS200`, `DDR52`) | `vmmc-supply = <&vddemmccore>` (`3.0 V` range) | `non-removable`, `cap-mmc-hw-reset`, `no-sd`, `no-sdio` |
| `&sdio0` | `mmc1` | 4-bit microSD (`UHS SDR104`, `SDR50`) | `vmmc-supply = <&vddsdcore>`, `vqmmc-supply = <&vddsdio>` | `cd-gpios = <&eic_sync 19 GPIO_ACTIVE_LOW>`, `no-sdio`, `no-mmc` |

Board-specific `sprd,phy-delay-*` properties in [`ums512-samsung-gtaba8.dts`](../linux/arch/arm64/boot/dts/sprd/ums512-samsung-gtaba8.dts#L265-L301) match Samsung's calibrated timing values for both controllers.

## Driver & Quirks (`sdhci-sprd`)

1. **Power Sequencing & UHS Tuning** (`96ec25d40e65`):
   - Fixed `sdhci-sprd` power sequencing, best-sample phase selection, and UHS tuning required for reliable eMMC `HS400ES` and microSD `SDR104` operation.
2. **DMA Descriptor Memory Barrier** (`71567259b932`):
   - Added explicit `dma_wmb()` before issuing `SDHCI_COMMAND` so ADMA/SDMA descriptors in coherent memory are visible to the SDHCI DMA engine before the command starts.
3. **EIC 8-Bank Support for Card Detect** (`69a135a7ac05`):
   - microSD card detection uses `&eic_sync 19`, requiring 8-bank EIC support in `gpio-eic-sprd`.
4. **SDIO Clock Auto-Gating Workaround** (`912692057c0a`):
   - See [`wifi.md`](wifi.md) — `CLK_AUTO` gating is suppressed only on SDIO-capable hosts (not on `no-sdio` eMMC/microSD hosts).
