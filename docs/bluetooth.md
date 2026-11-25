# Bluetooth 5.0 (`UWE5622` / `SC2355` Marlin3-Lite)

## Hardware & Software Stack

- **Controller**: Unisoc `UWE5622` / Marlin3-Lite Bluetooth 5.0 (`Manufacturer: 0x073f`, `Version: 0x09`), BR/EDR + BLE (`1M` / `2M` / `Coded` PHY, up to 16 advertising instances), shared CP2 die with Wi-Fi over `sdio1`.
- **Kernel Drivers**:
  - `sprdbt_tty.ko` (`sprd-mtty`, compatible `"sprd,mtty"`, `sprd,name = "ttyBT"`): creates `/dev/ttyBT0` and `/dev/ttyBT1`, manages BT rfkill (`MARLIN_BLUETOOTH`), and transports HCI packets over SDIO (`BT_TX_CHANNEL` / `BT_RX_CHANNEL`).
  - Mainline `hci_uart` (`CONFIG_BT_HCIUART=y`, `CONFIG_BT_HCIUART_H4=y`, `N_HCI=15`): `hci_uart_write_work` runs in sleepable workqueue context, compatible with `sprdbt_tty`'s `mtty_write()` which uses `down(&sem_id)` and `GFP_KERNEL`.
- **Firmware Files** (`firmware-samsung-gtaba8`, in `/usr/lib/firmware/uwe5622/`):
  - `bt_configure_pskey.ini` (44 fields, 160-byte PSKey configuration struct)
  - `bt_configure_rf.ini` (20 fields, 252-byte RF calibration & power table struct)
- **Userspace Attach Daemon & OpenRC Service** (`device-samsung-gtaba8` + `device-samsung-gtaba8-openrc`):
  - [`sprd-bt-attach.c`](../pmaports/device/testing/device-samsung-gtaba8/sprd-bt-attach.c) -> `/usr/bin/sprd-bt-attach`
  - [`sprd-bt.initd`](../pmaports/device/testing/device-samsung-gtaba8/sprd-bt.initd) -> `/etc/init.d/sprd-bt` (enabled in `default` runlevel `before bluetooth`)

## Quirks & Bring-Up Details

### 1. Soft-Blocked RFKill & `CONFIG_MEM_PD` Dependency
- `sprdbt_tty` (`rfkill.c`) initializes Bluetooth rfkill as soft-blocked (`rfkill_init_sw_state(bt_rfk, true)`).
- Unblocking Bluetooth invokes `start_marlin(MARLIN_BLUETOOTH)`, which depends on `CONFIG_MEM_PD` in `uwe5622_bsp_sdio.ko` (`633232305543`) to re-power BT IRAM, upload the saved `0x36200`-byte BT memory bin, and start CP2's BT thread (`bt_open int from cp` -> `cp bt creat thread ok`).

### 2. Required Vendor-Specific Commands (VSC) Before `N_HCI` Attach
Marlin3-Lite will not answer standard HCI commands (`hci0` never initializes) until three Unisoc VSC frames are sent directly over `/dev/ttyBT0`:
1. `0xFCA0` (160 B): packed little-endian PSKey block parsed from `bt_configure_pskey.ini`
2. `0xFCA2` (252 B): packed little-endian RF table parsed from `bt_configure_rf.ini`
3. `0xFCA1` (`0x00 0x00 0x01`): enable dual-mode BT controller

Once all three return Command Complete with `status=0x00`, `sprd-bt-attach` sets line discipline `N_HCI` (`TIOCSETD`) and H4 protocol (`HCIUARTSETPROTO`, `0`), creating `hci0` (`bluetoothd` picks it up immediately).

### 3. Mainline Linux Park Mode Quirk (`feature_set[1]`)
- Stock `bt_configure_pskey.ini` advertises legacy LMP Park capability (`feature_set` byte 1 = `0xFF`, offset 5 of the 160-byte PSKey struct).
- On mainline Linux BlueZ, `hci_init()` issues `Write_Default_Link_Policy` with Park mode enabled, which Marlin3 firmware rejects with status `0x12`, aborting `hci0` setup.
- `sprd-bt-attach` clears bit 0 (`pskey[5] &= ~0x01`, `0xFF -> 0xFE`) before sending `0xFCA0`.

### 4. Placeholder BD_ADDR Replacement
- `bt_configure_pskey.ini` ships with a fixed placeholder `device_addr = 0x6D, 0x6D, 0x8E, 0x8E, 0x8F, 0x8F` (PSKey offset `20..25`).
- `sprd-bt-attach` replaces placeholders / all-zero addresses with a deterministic locally-administered unicast BD_ADDR derived from `/etc/machine-id` (`mac[5] = (mac[5] & 0xfe) | 0x02`).

### 5. `pmbootstrap` Cross-Compile Note (`!pmb:crossdirect`)
- Building `sprd-bt-attach.c` inside `pmbootstrap` hit `cc: fatal error: cannot execute 'cc1': posix_spawnp: No such file or directory` under `crossdirect-aarch64`. [`device-samsung-gtaba8/APKBUILD`](../pmaports/device/testing/device-samsung-gtaba8/APKBUILD) sets `!pmb:crossdirect` in `options` (`3148179c6`) so `sprd-bt-attach` compiles cleanly inside the `aarch64` buildroot.
