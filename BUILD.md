# Building OpenWrt Package (.ipk)

This guide explains how to build a standalone `.ipk` package for OWLevelMeter.

## Prerequisites

- OpenWrt SDK (matching your router's architecture)
- Basic build tools (`make`, `gcc`)

## Step 1: Download SDK

```bash
# For MT7621 (common in routers)
wget https://downloads.openwrt.org/releases/21.02.3/targets/ramips/mt7621/openwrt-sdk-21.02.3-ramips-mt7621_gcc-8.4.0_musl.Linux-x86_64.tar.xz

# Extract
tar -xf openwrt-sdk-*.tar.xz
cd openwrt-sdk-*/
```

## Step 2: Create Package Directory

```bash
mkdir -p package/levelmeter
cd package/levelmeter
```

## Step 3: Create Makefile

Create `package/levelmeter/Makefile`:

```makefile
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-levelmeter
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Your Name <your@email.com>

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-levelmeter
	SECTION:=luci
	CATEGORY:=LuCI
	TITLE:=LuCI Level Meter App
	DEPENDS:=+lua +alsa-utils +alsa-lib +luci-base
	PKG_ARCH:=all
endef

define Package/luci-app-levelmeter/description
	Real-time audio level meter for OpenWrt with ALSA support
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/luci-app-levelmeter/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(CURDIR)/../../levelmeter-daemon.lua $(1)/usr/bin/levelmeter-daemon
	
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/../../etc/init.d/levelmeter $(1)/etc/init.d/levelmeter
	
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/../../etc/config/levelmeter $(1)/etc/config/levelmeter
	
	$(INSTALL_DIR) $(1)/usr/share/luci-app-levelmeter/luasrc/controller/admin
	$(INSTALL_DATA) $(CURDIR)/../../luci/controller/admin/levelmeter.lua $(1)/usr/share/luci-app-levelmeter/luasrc/controller/admin/
	
	$(INSTALL_DIR) $(1)/usr/share/luci-app-levelmeter/luasrc/model/cbi/admin
	$(INSTALL_DATA) $(CURDIR)/../../luci/model/cbi/admin/levelmeter.lua $(1)/usr/share/luci-app-levelmeter/luasrc/model/cbi/admin/
	
	$(INSTALL_DIR) $(1)/usr/share/luci-app-levelmeter/luasrc/view/admin
	$(INSTALL_DATA) $(CURDIR)/../../luci/view/admin/levelmeter_status.htm $(1)/usr/share/luci-app-levelmeter/luasrc/view/admin/
endef

$(eval $(call BuildPackage,luci-app-levelmeter))
```

## Step 4: Build

```bash
# Back to SDK root
cd ../..

# Copy files into package directory
cp -r ../luci package/levelmeter/
cp ../levelmeter-daemon.lua package/levelmeter/
cp -r ../etc package/levelmeter/

# Build
make package/levelmeter/compile V=s
```

## Step 5: Find Output

```bash
ls -lh bin/packages/*/luci-app-levelmeter*.ipk
```

## Step 6: Install on Router

```bash
scp bin/packages/*/luci-app-levelmeter*.ipk root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'opkg install /tmp/luci-app-levelmeter*.ipk'
```

## Done!

Restart LuCI and navigate to **System → Audio Level Meter**.
