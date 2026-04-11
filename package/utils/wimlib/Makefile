include $(TOPDIR)/rules.mk

PKG_NAME:=wimlib
PKG_VERSION:=1.14.5
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://wimlib.net/downloads/
PKG_HASH:=skip

PKG_BUILD_DEPENDS:=openssl
PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/wimlib
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=WIM library and tools
  URL:=https://wimlib.net/
  DEPENDS:=+libopenssl
endef

define Package/wimlib/description
  wimlib is a library for reading, writing, and extracting Windows Imaging (WIM) files.
  It provides the 'wimlib-imagex' command.
endef

define Package/wimlib/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/.libs/wimlib-imagex $(1)/usr/bin/
endef

define Package/wimlib/postinst
#!/bin/sh
[ -z "${IPKG_INSTROOT}" ] || exit 0
cd /usr/bin || exit 0
for cmd in append apply capture delete dir export extract info join mount mountrw optimize split unmount update verify; do
	[ -e "wim$$cmd" ] || ln -sf wimlib-imagex "wim$$cmd"
done
exit 0
endef

define Package/wimlib/prerm
#!/bin/sh
[ -z "${IPKG_INSTROOT}" ] || exit 0
cd /usr/bin || exit 0
for cmd in append apply capture delete dir export extract info join mount mountrw optimize split unmount update verify; do
	rm -f "wim$$cmd"
done
exit 0
endef

$(eval $(call BuildPackage,wimlib))
