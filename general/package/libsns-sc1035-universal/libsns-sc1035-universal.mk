################################################################################
#
# libsns-sc1035-universal
#
################################################################################

LIBSNS_SC1035_UNIVERSAL_VERSION = v1.4.0

LIBSNS_SC1035_UNIVERSAL_SITE = $(call github,MychkoM,libsns-sc1035-universal,$(LIBSNS_SC1035_UNIVERSAL_VERSION))
LIBSNS_SC1035_UNIVERSAL_LICENSE = MIT
LIBSNS_SC1035_UNIVERSAL_LICENSE_FILES = LICENSE

# Install after the osdrv package so our /etc/sensors/sc1035_960p.ini
# overwrites the stock prebuilt one.
LIBSNS_SC1035_UNIVERSAL_DEPENDENCIES = hisilicon-osdrv-hi3516cv100

LIBSNS_SC1035_UNIVERSAL_CFLAGS = \
	-Dhi3518 \
	-DHICHIP=0x35180100 \
	-DISP_V1 \
	-I$(@D)/include

define LIBSNS_SC1035_UNIVERSAL_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -Wall -Os -fPIC -shared \
		$(LIBSNS_SC1035_UNIVERSAL_CFLAGS) \
		-o $(@D)/libsns_sc1035_universal.so \
		$(@D)/src/sc1035_cmos.c \
		$(@D)/src/sc1035_sensor_ctl.c
endef

define LIBSNS_SC1035_UNIVERSAL_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib/sensors
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/sensors $(@D)/libsns_sc1035_universal.so

	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensors $(@D)/sc1035_960p.ini
endef

$(eval $(generic-package))
