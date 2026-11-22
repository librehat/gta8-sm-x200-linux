# firmware/

Only the hand-written reference notes are tracked here:

- `hardware_map.txt`: SoC, memory map, reserved memory and peripherals of the SM-X200
- `boot_img_info.txt`: boot image header layout, partition map and LK handoff behaviour

Everything else (stock DT/DTBO tables, decompiled downstream DTS, the live FDT,
`dtbo-noop.img`) comes from Samsung's images or from the device and is
git-ignored. Regenerate it with:

```bash
# Tablet booted into OrangeFox/TWRP recovery (root adb shell):
tools/extract-firmware.sh --pull

# Or from a Samsung firmware package (no live FDT):
tools/extract-firmware.sh --ap AP_X200*.tar.md5

# Re-run on the images already in firmware/backups/:
tools/extract-firmware.sh
```

Raw partition dumps go into `firmware/backups/`. The script only fetches
missing dumps and never overwrites existing ones unless you pass `--force`, so
the stock boot/dtbo backups stay safe after you flash custom images. Device
identifiers (serial number, `un`, `em.did`, `serial-number`) are masked in
`device_live.{dtb,dts}` unless you pass `--no-scrub`. The unmasked copy stays in
`firmware/backups/device_live-raw.dtb`.
