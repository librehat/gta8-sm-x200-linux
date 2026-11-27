# Hardware Support & Quirks (`SM-X200` / `SM-X205`)

Technical documentation for **Nura Edge** (postmarketOS-based) on the **Samsung Galaxy Tab A8 10.5 (2021)** (`SM-X200` Wi-Fi / `SM-X205` LTE), based on the **Unisoc Tiger T618** (`UMS512` / `sharkl5pro`) SoC and **Linux v7.3 LTS**.

## Subsystem Index

| Hardware | Document | Kernel Driver / Userspace | Status |
| :--- | :--- | :--- | :--- |
| Boot, SoC, Watchdog & Ramoops | [`boot.md`](boot.md) | `LK` handoff, `reloc.S`, `dtbo-noop`, `sc27xx_wdt`, `sc27xx-poweroff`, `ramoops` | Working |
| Storage (eMMC & microSD) | [`storage.md`](storage.md) | `sdhci-sprd` (`&sdio3`, `&sdio0`) | Working (eMMC); microSD untested |
| USB Peripheral Networking | [`usb.md`](usb.md) | `musb-sprd`, `phy-sprd-usb2`, ConfigFS RNDIS/ACM | Working |
| Display & GPU | [`display-and-gpu.md`](display-and-gpu.md) | `ums512_dpu_kms`, `panfrost` (`sprd,ums512-mali`), KWin | Working |
| Touchscreen & Physical Buttons | [`touchscreen.md`](touchscreen.md) | `nt36xxx` (`spi-sprd`), `gpio-keys` (`gpio-eic-sprd`, `sc2730` EIC) | Working |
| Battery Monitoring & Charging | [`battery-and-charging.md`](battery-and-charging.md) | `sc27xx_fuel_gauge`, `sgm4154x` (`i2c-sprd`) | Working |
| Wi-Fi (`UWE5622` / `SC2355`) | [`wifi.md`](wifi.md) | `uwe5622_bsp_sdio`, `sprdwl_ng` (`sdio1`) | Working |
| Bluetooth 5.0 (`UWE5622`) | [`bluetooth.md`](bluetooth.md) | `sprdbt_tty`, `hci_uart` (`N_HCI` H4), `sprd-bt-attach`, BlueZ | Working |
