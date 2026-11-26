# gta8-sm-x200-linux
Nura (Linux) port for Samsung Galaxy Tab A8 2021 SM-X200

## Development

Read `DEVELOPMENT.md` for information on setting up the development environment and building the port.

## AI Agents
AI Agents must read `AGENTS.md` and follow the instructions outlined there for all development work.

## Status

| Feature | Status |
| --- | --- |
| Storage | Working |
| Physical Buttons | Working |
| Display | Working |
| Touchscreen | Working |
| GPU | Parital |
| Audio | Not working |
| Wi-Fi | Working |
| Bluetooth | Working |
| Camera | Not working |
| Battery Monitoring | Working |
| Charging | Working |
| USB OTG | Untested |
| USB Networking | Working |
| Sensors | Untested |

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