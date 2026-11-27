# USB Peripheral & Gadget Networking

## Hardware Configuration

- **USB2 PHY**: `&hsphy` (`status = "okay"`, `phy-supply = <&vddusb33>`).
- **Controller**: `&usb` (`status = "okay"`, `dr_mode = "peripheral"` — Mentor Graphics `musb` on Unisoc UMS512).
- **Gadget Function**: ConfigFS USB gadget (`CONFIG_USB_CONFIGFS_RNDIS`, `CONFIG_USB_CONFIGFS_ECM`, `CONFIG_USB_CONFIGFS_NCM`, `CONFIG_USB_CONFIGFS_ACM`) bringing up `usb0` at `172.16.42.1/24` (host `172.16.42.2`, SSH `user@172.16.42.1` on the installed rootfs, or `root@172.16.42.1` / telnet in initramfs).
- **Host Script**: [`tools/usbnet-up.sh`](../tools/usbnet-up.sh) configures the host USB interface (`172.16.42.2/24`).

*(Note: USB OTG host mode (`dr_mode = "otg"`) is currently untested; [`ums512-samsung-gta8.dts`](../linux/arch/arm64/boot/dts/sprd/ums512-samsung-gta8.dts) enables `dr_mode = "peripheral"` plus `usb_otg_vbus` / `sgm4154x_otg_vbus` regulators for future OTG work.)*

## UMS512 PHY & MUSB Quirks

1. **Preserve Hardware PHY Trimming Register** (`217461deaa0d`, `92b8787d25e7`):
   - `phy-sprd-usb2` uses the UMS512 register table with cold-boot clock/reset initialization while preserving the factory-calibrated hardware trimming register (`217461deaa0d`) rather than overwriting it on init.
2. **Premature D+ Pull-Up Before Gadget Bind** (`cf5d4b960a20`, `3cac225a609d`):
   - `musb-sprd` previously asserted peripheral session / D+ pull-up too early before ConfigFS finished binding gadget functions, causing host enumeration failures (`device descriptor read/64`). Fixed so D+ pull-up stays masked until gadget bind completes.
3. **DMA Addressing, Alignment & EP0 FIFO Erratum** (`2a59249af331`, `5009ea3c3e7d`):
   - Fixed TX/RX DMA sequencing, 36-bit physical addressing, and the Unisoc MUSB EP0 FIFO erratum.
   - Set `MUSB_G_NO_SKB_RESERVE` so RX DMA writes into aligned SKB buffers instead of tripping unaligned DMA stalls.
4. **Wakeup IRQ Guard** (`468bf209f33c`):
   - Avoided unconditionally enabling the MUSB wakeup IRQ during probe.
5. **Disable Legacy `g_serial`** (`0f60ae12118b`, `a679256ac`):
   - Disabled built-in `CONFIG_USB_G_SERIAL` so it does not claim the single UDC before Nura Edge's ConfigFS gadget (`RNDIS` / `ACM`) binds.
