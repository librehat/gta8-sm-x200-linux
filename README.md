# gta8-sm-x200-linux
Nura (postmarketOS) Linux port for Samsung Galaxy Tab A8 2021 SM-X200

## Installation

Read `INSTALL.md` for instructions on installing and flashing this Nura Edge port onto the tablet.

## Development

Read `DEVELOPMENT.md` for information on setting up the development environment and building the port.

## AI Agents
AI Agents must read `AGENTS.md` and follow the instructions outlined there for all development work.

## Status

| Feature | Status |
| --- | --- |
| eMMC | Working |
| microSD | Not tested |
| Physical Buttons | Working |
| Display | Working |
| Touchscreen | Working |
| GPU | Working |
| Audio | Not working |
| Wi-Fi | Working |
| Bluetooth | Working |
| Camera | Not working |
| Battery Monitoring | Working |
| Charging | Working |
| USB OTG | Not working |
| USB Networking | Working |
| Sensors | Not working |
| Suspend / Deep Sleep | Working |

## Hardware Documentation

Subsystem notes, bring-up architecture, and SM-X200 hardware/driver quirks are documented under [`docs/`](docs/README.md):

- [Boot, SoC Platform, Watchdog & Ramoops](docs/boot.md)
- [Storage (eMMC & microSD)](docs/storage.md)
- [USB Peripheral & Gadget Networking](docs/usb.md)
- [Display & GPU](docs/display-and-gpu.md)
- [Touchscreen & Physical Buttons](docs/touchscreen.md)
- [Battery Monitoring & Charging](docs/battery-and-charging.md)
- [Wi-Fi (`UWE5622` / `SC2355`)](docs/wifi.md)
- [Bluetooth 5.0 (`UWE5622`)](docs/bluetooth.md)