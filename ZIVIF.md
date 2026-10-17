# ZIVIF board (hi3518ev200 + GC2033 DVP)

### 1. GPIO board wiring
| Function | Linux GPIO | Formula | Verified |
|---|---|---|---|
| IRCUT pin 1 | **GPIO57** | GPIO7_1 → 7×8+1 | ✅ confirmed |
| IRCUT pin 2 | **GPIO54** | GPIO6_6 → 6×8+6 | ✅ confirmed |
| Light sensor out (day/night input, was `irout`) | **GPIO56** | GPIO7_0 → 7×8+0 | ✅ confirmed |
| IR illuminator | **HARDWARE-AUTONOMOUS** | — | ✅ owner-confirmed 2026-10-17: the IR array has its own photodiode and power — it switches itself, the camera only READS the irout status (via GPIO56). No backlightPin in nightMode (correct — there is nothing for the camera to drive). Consequence: night shots are lit AND clean (flat-zone noise std 8–9). |

### 2. Majestic nightMode (applied, verified: set_gpio + hw sensor monitor)
```yaml
nightMode:
  enabled: true
  lightMonitor: true
  irCutPin1: 57        # IRCUT pin 1
  irCutPin2: 54        # IRCUT pin 2
  lightSensorPin: 56   # light sensor out
```

### 3. Sensor config — Mask_0 differs from upstream default (upstream ini is for Perenio)
| Board | Mask_0 | DVP bus | Source |
|---|---|---|---|
| **ZIVIF** (2 boards tested) | `0xFFF0000` | 12-bit (bits 16–27) | `/etc/sensors/gc2033_i2c_1080p.ini`, line 86 |
| Perenio PEIFC01 | `0x3FF0000` | 10-bit (bits 16–25) | upstream default: `general/package/hisilicon-osdrv-hi3516cv200/files/sensor/config/gc2033_i2c_1080p.ini` |

- Wrong mask on ZIVIF: `0x3FF0000` → magenta glitch block ~5–10% of center frame; vendor `0xffc00000` → full purple frame.
- Full sensor kit (libsns_gc2033.so + ini + load_hisilicon patch `| gc2033)` in DVP case, line 93): `/workspace/sensors-gc2033/`.

### 4. Sensor interface — DVP (parallel), confirmed; ini MIPI fields are dead weight
Active config fields:
| Field | Value | Meaning |
|---|---|---|
| `[mode] input_mode` | `4` | MIPI=0, SUBLVDS=1, LVDS=2 → 4 ≠ MIPI (DC mode) |
| `[vi_dev] Input_mod` | `2` | BT656=0, BT601=1, **DIGITAL_CAMERA=2** — parallel interface |
| `Mask_0` | `0xFFF0000` | bit-mask of parallel DATA bus — exists only in the DVP path |
| `[lvds]` section | all `-1` | disabled |

- `data_type`, `lane_id=0|1|-1…`, `dev_attr` sit under ini comment `;------only for mipi_dev------` → applied only when `input_mode=0`; ignored here. The note `(GC2033 is 2-lane MIPI)` is a template leftover, misleading.
- Proof DVP: (1) `Mask_0` visibly changes the picture (bus-width effect) — MIPI has lanes, not bit-masks; (2) `load_hisilicon` gc2033 sits in the DVP case (line 93, group with jxf23/ov9712/sc2235/gc2023, DATA-pad mux + DIR pin6); (3) MIPI-style config on a ZIVIF board gave IntCnt=0 + `Cannot set VI Mipi attr`, DVP gives 1080p30.
- GC2033 datasheet: DVP-only sensor (parallel 8/10-bit out). GalaxyCore MIPI parts are gc2053/gc2063 family.

### 5. Night profile — 20 fps (applied 2026-10-16)
Priority: night image quality over 30 fps.
- Sensor ini: `Isp_FrameRate = 20` (line 65; **MIPI dead-weight removed 2026-10-16: `[mipi]` section + `dev_attr` line deleted, HAL accepts it fine** — kit md5 `2b04013e…`) → exposure ceiling **33→50 ms** (+50% light per frame).
- VI: IntGapT ≈ **49989 µs**, max 50027 — rock-steady 20 fps from the sensor, no drops. **2026-10-17 FINAL: the earlier "kernel caps 1080p at 15" is RETRACTED — the 15 fps was caused by `jpeg.enabled: false`: with the JPEG venc channel disabled, majestic silently caps video0 h264 at 15 fps (drop 1-of-4, PTS 50+50+100). FURTHER FINAL (same day, full bisect on .243 — details and the full ladder in /workspace/openipc/AONI_E975.md §4): the jpeg-on unlock itself only works in majestic binaries up to 69671d4 (2026-09-25); from 17ec3ed (26.09) onward ALL binaries (26.09/01.10/09.10/16.10) keep 1080p at a flat 15 fps regardless of the JPEG channel (rootfs/kernel proven 100% innocent; `majestic.mk` pulls a FLOATING master from S3). .197 runs the 16.10 firmware with jpeg-off → 15 fps both by jpeg-off AND by the broken binary; nothing config-side changes that. The `h264 ...@20fps` log line and ffprobe rates are still CLAIMS — verify with `-count_frames` or `venc0_encoded_frames_total` in /metrics.**
- MJPEG/JPEG channel: **disabled per owner 2026-10-17 (owner decision; .197 stays this way until re-decided)** — NOTE: this choice caps video0 at 15 fps @1080p (see above); with jpeg-on the stream was honest 20 (the "yesterday it gave 1080@20" report was likely TRUE — jpeg was on by default back then). `/image.jpg` answers 503 with the channel off.
- Night pipeline verified end-to-end: light sensor GPIO56=`0` → `Change mode to NIGHT` → IRCUT off → IQ night profile loads (`[ir_3dnr]` active). IR lamp: HARDWARE-AUTONOMOUS, see §1 (the camera only reads its irout status).
- Stream (jpeg-off state): claimed `r_frame_rate=20/1`, no DTS anomalies; measured with jpeg off: 151 frames / 10 s = 15 fps, drop pattern 50+50+100 ms — the jpeg-gating effect, same as .243. With jpeg-on (flash default, as before 2026-10-17) expect honest 20 — re-verify when the camera is back online.
