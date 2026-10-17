# Perenio PEIFC01 (Hi3518EV200 / GC2033) — Board Notes

Board: **IPC18EV200_PT_V1.0** ("NIP-55F2B", manufactured by Shenzhen Hichip Vision Technology), SoC **Hisilicon Hi3518EV200**, sensor **GalaxyCore GC2033** (DVP parallel, RAW10, 1920x1080, BAYER_RGGB).

## Changes made

### 1. Sensor config fix — `gc2033_i2c_1080p.ini`
File: [general/package/hisilicon-osdrv-hi3516cv200/files/sensor/config/gc2033_i2c_1080p.ini](general/package/hisilicon-osdrv-hi3516cv200/files/sensor/config/gc2033_i2c_1080p.ini)

General facts about the GC2033 sensor on this board (corrected 2026-10-16 after live verification — earlier "MIPI" wording was wrong):
- Connected via a **DVP parallel bus** (10 data bits on this PCB). GC2033 is a DVP-only part; the ini's MIPI-looking fields (`dev_attr`, `data_type`, `lane_id`, comment "GC2033 is 2-lane MIPI") are inert template leftovers — they only apply when `input_mode=0`, while the working config uses `input_mode=4` + `Input_mod=2` (VI_INPUT_MODE_DIGITAL_CAMERA).
- Native resolution **1920x1080** (30 fps; the ZIVIF sibling board runs 20 fps for night exposure headroom — see ZIVIF.md).
- Bayer pattern is **RGGB**.
- IR-LED/IRCUT switching is fully external to the sensor driver and must be handled by board GPIOs (see pin table below).

The stock vendor file was misconfigured for a different PCB revision, causing a solid purple frame and a wrong framerate. Fixed:
- `DllFile = libsns_gc2033.so`
- `Isp_FrameRate = 30` (was `15`)
- `Isp_Bayer = 0` — RGGB (was `1` — GRBG, wrong pattern causing the color tint)
- `Mask_0 = 0x3FF0000` — DVP DATA-bus bit-mask, bits 16–25 = 10-bit wiring on this PCB (was `0xffc00000`, a mask for a different DVP pinout → full purple frame). On the 12-bit ZIVIF boards the same field needs `0xFFF0000` — see ZIVIF.md.
- (`dev_attr`, `data_type`, `lane_id` + the whole `[mipi]` section were **removed from the repo file** on 2026-10-16 — md5 `f8665d4c…`, git diff = 13 deletions, 0 insertions; HAL parses the file fine without them, verified live. ZIVIF boards still need post-flash per-board overrides: `Mask_0=0xFFF0000`, night fps — see ZIVIF.md.)


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

### 4. Frame-rate chain on hi3518ev200 / majestic (verified 2026-10-16)
Why "30 fps in the config" can be 20 fps in the stream:
- **SoC budget**: hi3518ev200 carries ~**30× 1920x1080 frames/sec across ALL streams combined** (majestic enforces it; message: "this SoC carries %u 1920x1080 frames a second across its streams"). Default split: h264@20 + MJPEG@5.
- **venc default = 20** when `video0.fps` is not set; `r_frame_rate` in RTSP still advertises the sensor rate → the mismatch is invisible until you count frames (`avg_frame_rate`).
- **Night AE slow_shutter**: long exposure (e.g. 125000 µs ≈ 8 fps worth) forces frame drops BEFORE the encoder (venc `UserGet` vs `GetTimes` gap) → duplicate-DTS pairs in the stream (`ffmpeg: non monotonically increasing dts`), unstable output rate.
- **Fix for a true 30**: disable the MJPEG stream, `cli -s .video0.fps 30` → clean 30/30, DTS errors gone.
- **Fix for better night footage**: `Isp_FrameRate 30→20` in the sensor ini → exposure ceiling 33 ms→50 ms (+50% light per frame), VI IntGapT ≈ 49989 µs rock-steady, venc auto-caps to the sensor rate. Applied on the ZIVIF board (see ZIVIF.md §5).
- Night pipeline on this family end-to-end: light-sensor GPIO → majestic `Change mode to NIGHT` → IRCUT off → IQ night profile (`[ir_3dnr]`) loads.
