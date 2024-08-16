################################################################################
#
# rtl8188eu
#
################################################################################

RTL8188EU_OLD_SITE_METHOD = git
RTL8188EU_OLD_SITE = https://github.com/lwfinger/rtl8188eu
RTL8188EU_OLD_VERSION = f5d1c8df2e2d8b217ea0113bf2cf3e37df8cb716 # master, functional

RTL8188EU_OLD_LICENSE = GPL-2.0, proprietary (rtl8188fufw.bin firmware blob)
RTL8188EU_OLD_LICENSE_FILES = COPYING
RTL8188EU_OLD_MODULE_MAKE_OPTS = CONFIG_RTL8188EU=m
define RTL8188EU_OLD_INSTALL_FIRMWARE
	$(INSTALL) -D -m 644 $(RTL8188EU_OLD_PKGDIR)/rtl8188fufw.bin \
		$(TARGET_DIR)/lib/firmware/rtlwifi/rtl8188fufw.bin
endef
RTL8188EU_OLD_POST_INSTALL_TARGET_HOOKS += RTL8188EU_OLD_INSTALL_FIRMWARE

$(eval $(kernel-module))
$(eval $(generic-package))
