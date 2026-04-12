#!/bin/bash
# DIY Part 2: Execute before make

# Avoid literal glob when no files match (git bash on Windows)
shopt -s nullglob

echo "DIY Part 2: Custom settings"

# Modify default hostname
echo "Setting hostname to JDCloud..."
sed -i 's/ImmortalWrt/JDCloud/g' package/base-files/files/bin/config_generate

# Modify default timezone
echo "Setting timezone to Asia/Shanghai..."
sed -i 's/UTC/CST-8/g' package/base-files/files/bin/config_generate
sed -i 's|/usr/bin/ntpdate|/usr/sbin/ntpdate|g' package/base-files/files/bin/config_generate 2>/dev/null || true

# Clear root password (ensure empty password)
echo "Clearing root password..."
sed -i 's/root:.*/root:::0:99999:7:::/g' package/base-files/files/etc/shadow

# Fix fail2ban build error (Cannot import setuptools.build_meta)
echo "Fixing fail2ban build dependencies..."
FAIL2BAN_MAKEFILE="feeds/packages/net/fail2ban/Makefile"
if [ -f "$FAIL2BAN_MAKEFILE" ]; then
    if grep -q "PKG_BUILD_DEPENDS" "$FAIL2BAN_MAKEFILE"; then
        sed -i 's/PKG_BUILD_DEPENDS:=/PKG_BUILD_DEPENDS:=python3\/host python-setuptools\/host python-wheel\/host /' "$FAIL2BAN_MAKEFILE"
    else
        sed -i '/include $(TOPDIR)\/rules.mk/a PKG_BUILD_DEPENDS:=python3\/host python-setuptools\/host python-wheel\/host' "$FAIL2BAN_MAKEFILE"
    fi
    echo "  fail2ban Makefile patched: $(grep PKG_BUILD_DEPENDS "$FAIL2BAN_MAKEFILE")"
else
    echo "  WARNING: fail2ban Makefile not found at $FAIL2BAN_MAKEFILE"
fi

# ============================================================
# NSS hardware acceleration CONFIG flags
# Only inject if NSS driver is enabled but flags are missing
# ============================================================
echo "Checking NSS hardware acceleration flags..."
if grep -q 'CONFIG_PACKAGE_kmod-qca-nss-drv=y' .config 2>/dev/null; then
    if ! grep -q 'CONFIG_NSS_DRV=y' .config 2>/dev/null; then
        echo "  Injecting NSS CONFIG flags..."
        sed -i '/CONFIG_NSS_DRV/d' .config
        sed -i '/CONFIG_NSS_MEM_PROFILE/d' .config
        cat >> .config <<'NSEOF'
CONFIG_NSS_DRV=y
CONFIG_NSS_DRV_BRIDGE_ENABLE=y
CONFIG_NSS_DRV_VLAN_ENABLE=y
CONFIG_NSS_DRV_GRE_ENABLE=y
CONFIG_NSS_DRV_IPV6_ENABLE=y
CONFIG_NSS_DRV_PPPOE_ENABLE=y
CONFIG_NSS_DRV_SHAPER_ENABLE=y
CONFIG_NSS_MEM_PROFILE_MEDIUM=y
NSEOF
        echo "  NSS flags written to .config"
    else
        echo "  NSS flags already present in .config, skipping injection"
    fi
else
    echo "  NSS driver not in .config, skipping NSS flags"
fi

# ============================================================
# MgrServer: ensure files overlay permissions
# ============================================================
echo "Setting MgrServer file permissions..."
if [ -d "$GITHUB_WORKSPACE/files" ]; then
    # Ensure all uci-defaults scripts are executable
    for f in "$GITHUB_WORKSPACE/files/etc/uci-defaults/"*; do
        if [ -f "$f" ]; then
            chmod 0755 "$f"
            echo "  chmod 0755 $(basename "$f")"
        fi
    done

    # Ensure init.d scripts are executable
    for f in "$GITHUB_WORKSPACE/files/etc/init.d/"*; do
        if [ -f "$f" ]; then
            chmod 0755 "$f"
            echo "  chmod 0755 $(basename "$f")"
        fi
    done

    # Report MgrServer bundle size if present
    if [ -d "$GITHUB_WORKSPACE/files/root/mgrserver" ]; then
        MGR_SIZE=$(du -sh "$GITHUB_WORKSPACE/files/root/mgrserver" | awk '{print $1}')
        echo "  MgrServer bundle size: $MGR_SIZE"
    else
        echo "  WARNING: MgrServer bundle not found at files/root/mgrserver"
    fi

    # Report PXE resources size if present
    if [ -d "$GITHUB_WORKSPACE/files/home/pxe" ]; then
        PXE_SIZE=$(du -sh "$GITHUB_WORKSPACE/files/home/pxe" | awk '{print $1}')
        echo "  PXE resources size: $PXE_SIZE"
    fi
fi

# ============================================================
# Add factory.bin for JDCloud RE-SS-01 (eMMC device)
# Note: openwrt-24.10 may already have factory.bin support
# ============================================================
echo "Checking factory.bin support for JDCloud RE-SS-01..."
IPQ60XX_MK="target/linux/qualcommax/image/ipq60xx.mk"
if [ -f "$IPQ60XX_MK" ]; then
    # Check if device exists
    if grep -q "define Device/jdcloud_re-ss-01" "$IPQ60XX_MK"; then
        # Check if factory.bin is already defined
        if grep -A 20 "define Device/jdcloud_re-ss-01" "$IPQ60XX_MK" | grep -q "IMAGE/factory.bin"; then
            echo "  factory.bin already defined, skipping"
        else
            echo "  Attempting to add factory.bin support..."
            # Try to add factory.bin using awk
            awk '
            /^define Device\/jdcloud_re-ss-01/ { in_block=1 }
            in_block && /^endef/ {
                print "\t$(call Device/EmmcImage)"
                print "\tIMAGE/factory.bin := append-kernel | pad-to $$(KERNEL_SIZE) | append-rootfs | append-metadata"
                in_block=0
            }
            { print }
            ' "$IPQ60XX_MK" > "$IPQ60XX_MK.tmp" 2>/dev/null
            
            if [ $? -eq 0 ] && [ -f "$IPQ60XX_MK.tmp" ]; then
                mv "$IPQ60XX_MK.tmp" "$IPQ60XX_MK"
                if grep -A 20 "define Device/jdcloud_re-ss-01" "$IPQ60XX_MK" | grep -q "IMAGE/factory.bin"; then
                    echo "  ✓ factory.bin generation added to jdcloud_re-ss-01"
                else
                    echo "  ⚠ factory.bin patch may have failed, but continuing..."
                fi
            else
                echo "  ⚠ Could not patch factory.bin, but continuing build..."
                rm -f "$IPQ60XX_MK.tmp"
            fi
        fi
    else
        echo "  WARNING: jdcloud_re-ss-01 device not found in $IPQ60XX_MK"
    fi
else
    echo "  WARNING: $IPQ60XX_MK not found"
fi

# ============================================================
# Node.js version selection (nxhack feeds)
# Use Node.js 24.x with GCC 15/16 compatibility fixes
# ============================================================
echo "Configuring Node.js version..."

# 使用 Node.js 24.x (nxhack feeds 已包含 GCC 15/16 修复)
echo "CONFIG_NODEJS_24=y" >> .config

# 禁用旧版本
sed -i '/^CONFIG_NODEJS_20=/d' .config
sed -i '/^CONFIG_PACKAGE_node-20=/d' .config

# 确保使用 small ICU (节省空间)
echo "CONFIG_NODEJS_ICU_SMALL=y" >> .config

# 重新生成配置
make defconfig

echo "Node.js 24.x configuration complete"

echo "DIY Part 2: Done"
