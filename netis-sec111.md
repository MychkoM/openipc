# Netis SEC111 (hi3518ev100) — branch changes

Branch: `feature/hi3518ev100-rtl` ·

This document describes what was changed for the Netis SEC111 camera and
why.

## Changed files (vs `master`)

| File | Change | Purpose |
|---|---|---|
| `br-ext-chip-hisilicon/board/hi3516cv100/hi3518ev100.generic.config` | RTL8192 (SE/CU/WIFI) disabled, **RTL8188EU enabled** (`CONFIG_R8188EU=m`, `CONFIG_88EU_AP_MODE=y`) | use the onboard Realtek 8188 WLAN instead of RTL8192 parts |
| `br-ext-chip-hisilicon/configs/hi3518ev100_lite_defconfig` | MediaTek **MT7601U removed**, **RTL8188EU added** (`BR2_PACKAGE_RTL8188EU=y`, firmware `RTL_8188EU=y`) | replace the MT7601U driver with the board's actual RTL8188EU adapter |
| `general/package/hisilicon-osdrv-hi3516cv100/files/script/load_hisilicon` | new `reset_sensor()` (devmem to 0x200f0124, 0x20140400, 0x20140008), called on `insert_ko` | hard-reset the SC1035 sensor at SDK load; without it the sensor fails to start and holds the I2C bus busy |
| `general/package/hisilicon-osdrv-hi3516cv100/files/sensor/config/sc1035_960p.ini` | `Isp_H` 720→**960** | native 1280×960@30fps sensor mode (matches camera panel) |

## Wired adapter (hieth) — u-boot env requirements

The wired port on this board does **not** come up without the correct
`hieth.*` kernel parameters. These are supplied via the u-boot `extras`
env var, which is appended to `bootargs`. Verified on camera 192.168.1.145
with `fw_printenv`:

```
extras=hieth.mdioifu=0 hieth.mdioifd=0 hieth.phyaddru=1 hieth.phyaddrd=2
```

| Param | Value | Meaning |
|---|---|---|
| `hieth.mdioifu` | 0 | MDIO interface, up port: 0 = MII |
| `hieth.mdioifd` | 0 | MDIO interface, down port: 0 = MII |
| `hieth.phyaddru` | 1 | external PHY address, up |
| `hieth.phyaddrd` | 2 | external PHY address, down |

Kernel confirms them on boot (`dmesg`):
`PHY probing DOWN_PORT hieth_mdio_if_u=0, hieth_mdio_if_d=0, hieth_phyaddr_u=1, hieth_phyaddr_d=2`
→ `PHY: himii:01 - Link is Up - 100/Full`.

## WIFI network adapter

The board carries a **Realtek RTL8188EU** wireless chipset (not MediaTek),
so the kernel config and Buildroot package selection were switched to it.

Why it was replaced rather than added alongside: the little flash / kernel
size budget does not fit **both** WiFi drivers, and this camera's actual chip
is RTL8188EU — so the MediaTek MT7601U driver was dropped to make room for
Realtek.

* Kernel driver: `CONFIG_R8188EU=m` (with `CONFIG_88EU_AP_MODE=y`)
* Userspace package: `BR2_PACKAGE_RTL8188EU=y`, firmware `BR2_PACKAGE_LINUX_FIRMWARE_OPENIPC_RTL_8188EU=y`
* Disabled: `RTL8192SE`, `RTL8192CU`, `RTLWIFI`, `RTL8192C_COMMON`, MediaTek `MT7601U`
* WLAN stays enabled (`CONFIG_WLAN=y`); wpa_supplicant is present in defconfig.

## GPIO pin map (as configured on camera 192.168.1.145, majestic.yaml)

| Name | Value | Direction | Function |
|---|---|---|---|
| `nightMode.irCutPin1` | **4** | out (value 0) | IR-cut motor, phase 1 |
| `nightMode.irCutPin2` | **2** | out (value 0) | IR-cut motor, phase 2 |
| `nightMode.lightSensorPin` | **6** | – | Inverted ambient-light sensor output |
| `nightMode.irLedPin` / `backlightPin` | **not used** | – | backlight/LED board pin is **not connected** — no accepting pin on the SoC; the IR LEDs are driven by the board's own photoresistor directly, with no SoC involvement |

Notes:

* Only `gpio2` and `gpio4` are exported as GPIOs on the camera
  (dir=out, value=0); all other gpiochip lines are unexported.
* The backlight board connected to the `gpio6` to the SoC**: the
  illuminator is self-powered via its onboard photoresistor, so `backlightPin`
  / `irLedPin` is deliberately left unassigned. Do not assign it in config.
* Day/night is controlled by inverted `gpio6` light monitor (`lightMonitor: true`).

## Camera runtime setup

* osmem `36M` / MMZ `28M` (set via u-boot env `osmem`)
* video `1280x960@20fps`, h264 `1024kbit`
