# Battery Monitoring & Charging

## Hardware & DTS

| Component | DTS Node / Bus | Driver | Key Parameters |
| :--- | :--- | :--- | :--- |
| Battery Fuel Gauge | `&sc2730_fgu` (`SC2730` PMIC) | `sc27xx_fuel_gauge` | `sprd,calib-resistance-micro-ohms = <10000>`, `sprd,comp-resistance-mohm = <26>`, 22-point NTC voltage-temp table |
| Battery Model | `bat: battery` (`simple-battery`) | Power supply core | Lithium-ion, `6804000 uAh` design capacity, `4.4 V` max (`4400000 uV`), 21-point `ocv-capacity-table-0` (`4.354 V`..`3.400 V`), `resistance-temp-table` |
| Switching Charger | `sgm41542_chg: charger@3b` on `&i2c4` (`0x70700000`, addr `0x3b`) | `sgm4154x` | IRQ `&ap_gpio 156 IRQ_TYPE_EDGE_FALLING`, `input-current-limit-microamp = <1500000>`, `input-voltage-limit-microvolt = <4500000>`, `sgm4154x-otg-vbus` regulator (`4.85`–`5.3 V`) |

See [`ums512-samsung-gtaba8.dts`](../linux/arch/arm64/boot/dts/sprd/ums512-samsung-gtaba8.dts#L202-L223) and [`#L383-L420`](../linux/arch/arm64/boot/dts/sprd/ums512-samsung-gtaba8.dts#L383-L420).

## Quirks & Fixes

1. **`i2c-sprd` Controller Transfer/NACK Enable** (`7fdc64c7f47e`):
   - `i2c-sprd` required enabling `I2C_TRANS_EN` and `I2C_NACK_EN` controller bits so I2C4 transactions with the `SGM41542` charger IC work reliably.
2. **`SC2730` Global Registers & NTC Temperature Table** (`bd08ecea06a0`, `5b1b01b6a472`):
   - Added `SC2730` support to `sc27xx_fuel_gauge`, fixed `SC2730` global register offsets, added the NTC thermistor `sprd,voltage-temp-table` lookup, and added a power-supply status fallback.
3. **Current Sign & Capacity Calibration Quirks** (`4311fc2398a0`, `1949cdd99333`, `ce856e42a301`, `f02caf23e855`, `7f72c9f61f86`):
   - Fixed signed handling of negative `CURRENT_NOW` readings during discharge.
   - Ignore stale fractional capacity saved across Android/mainline reboots and automatically calibrate FGU on every boot.
   - Force valid `[0..100]%` capacity clamping and update `CHARGE_COUNTER` alongside capacity updates.
4. **Fuel Gauge ↔ Charger DT Linking** (`b0171211ea90`, `3a1c874a3819`):
   - Added `power-supplies = <&sgm41542_chg>` on `&sc2730_fgu` and ensured `power_supply` core honors `supplied-from` with `CONFIG_OF=y`.
