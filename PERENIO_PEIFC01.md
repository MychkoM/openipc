# Perenio PEIFC01 (Hi3518EV200 / GC2033) — Board Notes

Board: **IPC18EV200_PT_V1.0** ("NIP-55F2B", manufactured by Shenzhen Hichip Vision Technology), SoC **Hisilicon Hi3518EV200**, sensor **GalaxyCore GC2033** (2-lane MIPI, RAW10, 1920x1080@30fps, BAYER_RGGB).

## Changes made

### 1. Sensor config fix — `gc2033_i2c_1080p.ini`
File: [general/package/hisilicon-osdrv-hi3516cv200/files/sensor/config/gc2033_i2c_1080p.ini](general/package/hisilicon-osdrv-hi3516cv200/files/sensor/config/gc2033_i2c_1080p.ini)

General facts about the GC2033 sensor on this board:
- Connected via **MIPI CSI-2**, 2 data lanes, RAW10 output — not DVP.
- Native resolution **1920x1080 @ 30fps**.
- Bayer pattern is **RGGB**.
- IR-LED/IRCUT switching is fully external to the sensor driver and must be handled by board GPIOs (see pin table below).

The file was misconfigured for a DVP sensor instead of MIPI, causing wrong colors (purple/magenta tint) and a wrong framerate. Fixed:
- `DllFile = libsns_gc2033.so`
- `dev_attr = 0` (MIPI, was `2`)
- Added `[mipi]` section: `data_type = 2`, `lane_id = 0|1|-1|-1|-1|-1|-1|-1|`
- `Isp_FrameRate = 30` (was `15`)
- `Isp_Bayer = 0` — RGGB (was `1` — GRBG, wrong pattern causing the color tint)
- `Mask_0 = 0x3FF0000` (MIPI mask, was `0xffc00000` — DVP mask)


### 2. GPIO board wiring
| Function | Linux GPIO | Formula | Verified |
|---|---|---|---|---|
| IRCUT pin 1 | **GPIO2** | GPIO0_2 → 0×8+2 | ✅ confirmed |
| IRCUT pin 2 | **GPIO1** | GPIO0_1 → 0×8+1 | ✅ confirmed |
| Light sensor (day/night input) | **GPIO62** (inverted) | GPIO7_6 → 7×8+6 | ✅ confirmed |
| Camera light (IR LED control, `irctl`) | **GPIO63** | GPIO7_7 → 7×8+7 | ✅ confirmed (LED changed) |
| Microphone | — (no GPIO) | — | Analog/I2S input via Hisilicon acodec, no enable GPIO |
| Speaker | — (no GPIO) | — | Always enabled in hardware; volume/mute is software-only (ALSA) |

### 3. WiFi (MT7601U) freezes under sustained load — switch to the MediaTek proprietary driver
Files: [general/package/mt7601u-openipc](general/package/mt7601u-openipc), [br-ext-chip-hisilicon/configs/hi3518ev200_lite_defconfig](br-ext-chip-hisilicon/configs/hi3518ev200_lite_defconfig), [general/overlay/etc/wireless/usb](general/overlay/etc/wireless/usb)

The onboard WiFi module is a **MediaTek MT7601U** USB dongle (`lsusb` ID `148f:7601`). Reported symptom: firmware downloads over WiFi stall at 30-50%, and under sustained load the **entire `wlan0` interface freezes** (no ping, no new SSH connections; throughput collapses from ~480KB/s to a stall).
- No hardware-level recovery or power-cycling is possible.
- The freeze is in the **in-kernel mainline `mt7601u` driver** (mac80211/cfg80211 stack) used by this OpenIPC image. It is a different codebase from the driver the camera's stock firmware uses.

**Root cause / comparison with stock firmware (checked 2026-09-20):**
- The vendor's `neo_original` dump ships the **MediaTek proprietary Ralink driver** (`mt7601Usta.ko` + `mtprealloc.ko`), built for kernel **3.4.35 ARMv5 p2v8**. Vendor Buildroot `hi35xx-buildroot` (`nip22f2g_defconfig`, kernel 3.4.35) builds the same via `BR2_PACKAGE_MT7601U=y`.
- **Cannot copy the vendor binary onto OpenIPC**: it fails with `mtprealloc: version magic '3.4.35 ...' should be '4.9.37 mod_unload ARMv5 p2v8 '` (verified live via `insmod`).
- **Cannot copy a prebuilt `mt7601sta.ko` from another OpenIPC board either**: the hi3516ev300 release ships `mt7601sta.ko` built for **`4.9.37 ARMv7 p2v8`** (verified its vermagic), but this board's kernel is **ARMv5 p2v8**. Same kernel number, different CPU arch — module won't load. So the proprietary driver must be **compiled for this exact board**, which is what `BR2_PACKAGE_MT7601U_OPENIPC=y` does at image build time.

**Chosen fix — compile the MediaTek proprietary driver into the firmware**:
- `BR2_PACKAGE_MT7601U_OPENIPC=y` in `hi3518ev200_lite_defconfig`. This is OpenIPC's maintained fork of the same proprietary driver (`github.com/openipc/mt7601u`, commit `0ac4655`, MediaTek `JEDI.MP1.mt7601u.v1.12.2.3`, RTMP/RT2870 codebase), built by kbuild against the board's own kernel → correct ARMv5 4.9.37 vermagic.
- `general/overlay/etc/wireless/usb`: profile `mt7601sta-generic` → `modprobe mt7601sta` (binds the proprietary module; in-kernel `mt7601u` stays present but unbound). The fork registers the interface as **`wlan0`** (built with `RT_CFG80211_SUPPORT`), so no rename / network-config changes are needed.
- Kernel config on this board already has what the driver needs: `CONFIG_WIRELESS_EXT`, `WEXT_CORE`, `CFG80211=m`, `FW_LOADER`, `UEVENT_HELPER`. (`CFG80211_WEXT` off is fine — the fork registers via cfg80211 directly.)
- On the camera after flashing: `fw_setenv wlandev mt7601sta-generic`.

**Status** (as of 2026-09-20): defconfig + wireless profile changes are in the working tree, ready for a **CI/rebuild+flash**; the driver will only be built for this board by compiling it with the firmware (no prebuilt `.ko` can be dropped in due to the ARMv5 kernel). After flashing, verify with the 200MB load test and compare against the logs of the current mainline driver.
