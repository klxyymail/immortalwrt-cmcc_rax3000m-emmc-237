#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#              本脚本在 OpenWrt 源码根目录(./openwrt)下执行
#

# 添加feed源函数
# 参数1: feed名称
# 参数2: feed URL
add_feed() {
    local name=$1
    local url=$2
    # 检查feeds.conf.default中是否已包含该源
    if ! grep -q "src-git $name $url" feeds.conf.default; then
        echo "添加feed源：$name，地址：$url"
        echo "src-git $name $url" >> feeds.conf.default
    else
        echo "ℹ️ feed源 $name 已存在，跳过添加"
    fi
}

# 添加istore和nas_luci源
add_feed "istore" "https://github.com/linkease/istore.git;main"
add_feed "nas_luci" "https://github.com/linkease/nas-packages-luci.git;main"
add_feed "nas_packages" "https://github.com/linkease/nas-packages.git;master"

# 克隆第三方包函数
# 参数1: 仓库URL
# 参数2: 目标目录
clone_package() {
    local repo=$1
    local dir=$2
    
    # 如果目录已存在，先删除（强制覆盖）
    if [ -d "$dir" ]; then
        echo "⚠️ 包 $dir 已存在，删除旧版本并重新克隆..."
        rm -rf "$dir" || {
            echo "❌ 删除旧版本 $dir 失败！"
            exit 1
        }
    fi
    
    # 执行克隆（无论之前是否存在目录）
GIT_CLONE_OUTPUT=$(git clone --depth 1 "$repo" "$dir" 2>&1)
CLONE_EXIT_CODE=$?
if [ $CLONE_EXIT_CODE -eq 0 ]; then
    echo -e "✅ 克隆包：$repo 到 $dir 成功！"
else
    echo -e "❌ 克隆包：$repo 到 $dir 失败！"
    echo -e "❌ 错误信息：$GIT_CLONE_OUTPUT"
    exit 1
fi
}

# 克隆所需第三方包
clone_package "https://github.com/gdy666/luci-app-lucky.git" "package/luci-app-lucky"
clone_package "https://github.com/tty228/luci-app-wechatpush.git" "package/luci-app-wechatpush"
clone_package "https://github.com/rogueme/luci-app-adguardhome.git" "package/luci-app-adguardhome"
clone_package "https://github.com/sirpdboy/luci-app-taskplan.git" "package/luci-app-taskplan"
# 克隆mentohust解决luci-app-airwhu缺失依赖的警告
clone_package "https://github.com/KyleRicardo/MentoHUST-OpenWrt-ipk.git" "package/mentohust"
# 克隆 Harbor File pro（Windows 风格文件管理器，对应 CONFIG_PACKAGE_luci-app-harbor-file-pro）
clone_package "https://github.com/whzhni1/luci-app-harbor-file-pro.git" "package/luci-app-harbor-file-pro"

# ==========================================================================
# 新增 CMCC XR30 eMMC（RAX3000Z 增强版）设备 profile：cmcc_xr30-emmc
#
# 说明：
#   XR30 eMMC 与 RAX3000M eMMC 硬件完全一致（MT7981B + DDR4 512M + 64G eMMC
#   + MT7531 + MT7976C），唯一区别是 LED：
#       RAX3000M eMMC：绿 pio9 / 蓝 pio12 / 红 pio35
#       XR30   eMMC：白 pio34（投影灯）/ 红 pio35
#   因此这里以 mt7981b-cmcc-rax3000m-emmc-mtk.dts 为蓝本新建一个 dts，
#   保留 eMMC/mmc0、factory 分区（MAC / eeprom）、网络交换、USB 等全部配置，
#   只改机型名、compatible 和 LED，并新增独立的设备 profile，
#   使固件文件名、board_name 都正确显示为 XR30。
#
#   本段在 make defconfig 之前执行（diy-part1 早于 .config 加载），
#   因此新增的 profile 能被正常识别。
# ==========================================================================

MK_FILE="target/linux/mediatek/image/filogic.mk"
DTS_DIR="target/linux/mediatek/dts"
DTS_FILE="$DTS_DIR/mt7981b-cmcc-xr30-emmc.dts"
SMP_FILE="package/mtk/applications/mtk-smp/files/smp.sh"
UBOOTENV_FILE="package/boot/uboot-envtools/files/mediatek"

if [ ! -f "$MK_FILE" ]; then
    echo "❌ 未找到 $MK_FILE，无法新增 XR30 eMMC 设备，终止编译！"
    exit 1
fi

# ---------- 1. 写入设备树 ----------
mkdir -p "$DTS_DIR"
cat > "$DTS_FILE" <<'DTSEOF'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
/*
 * CMCC XR30 eMMC (RAX3000Z 增强版) - MTK U-Boot layout
 * 基于 mt7981b-cmcc-rax3000m-emmc-mtk.dts
 * 硬件与 RAX3000M eMMC 相同，差异仅在 LED：白 pio34（投影灯）/ 红 pio35
 */

/dts-v1/;
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>
#include <dt-bindings/leds/common.h>

#include "mt7981.dtsi"

/ {
	model = "CMCC XR30 eMMC";
	compatible = "cmcc,xr30-emmc", "mediatek,mt7981";

	aliases {
		led-boot = &red_led;
		led-failsafe = &red_led;
		led-running = &white_led;
		led-upgrade = &white_led;
		serial0 = &uart0;
	};

	chosen: chosen {
		bootargs = "root=PARTLABEL=rootfs rootwait rootfstype=squashfs,f2fs";
		stdout-path = "serial0:115200n8";
	};

	memory {
		reg = <0 0x40000000 0 0x20000000>;
	};

	gpio-keys {
		compatible = "gpio-keys";

		button-reset {
			label = "reset";
			linux,code = <KEY_RESTART>;
			gpios = <&pio 1 GPIO_ACTIVE_LOW>;
		};

		button-mesh {
			label = "mesh";
			linux,code = <BTN_9>;
			linux,input-type = <EV_SW>;
			gpios = <&pio 0 GPIO_ACTIVE_LOW>;
		};
	};

	gpio-leds {
		compatible = "gpio-leds";

		white_led: led-0 {
			function = LED_FUNCTION_STATUS;
			color = <LED_COLOR_ID_WHITE>;
			gpios = <&pio 34 GPIO_ACTIVE_LOW>;
		};

		red_led: led-1 {
			function = LED_FUNCTION_STATUS;
			color = <LED_COLOR_ID_RED>;
			gpios = <&pio 35 GPIO_ACTIVE_LOW>;
		};
	};
};

&mmc0 {
	bus-width = <8>;
	cap-mmc-highspeed;
	max-frequency = <52000000>;
	non-removable;
	pinctrl-names = "default", "state_uhs";
	pinctrl-0 = <&mmc0_pins_default>;
	pinctrl-1 = <&mmc0_pins_uhs>;
	vmmc-supply = <&reg_3p3v>;
	status = "okay";

	card@0 {
		compatible = "mmc-card";
		reg = <0>;

		block {
			compatible = "block-device";

			partitions {
				block-partition-factory {
					partname = "factory";

					nvmem-layout {
						compatible = "fixed-layout";
						#address-cells = <1>;
						#size-cells = <1>;

						eeprom_factory_0: eeprom@0 {
							reg = <0x0 0x1000>;
						};

						macaddr_factory_24: macaddr@24 {
							compatible = "mac-base";
							reg = <0x24 0x6>;
							#nvmem-cell-cells = <1>;
						};

						macaddr_factory_2a: macaddr@2a {
							compatible = "mac-base";
							reg = <0x2a 0x6>;
							#nvmem-cell-cells = <1>;
						};
					};
				};
			};
		};
	};
};

&eth {
	status = "okay";

	gmac0: mac@0 {
		compatible = "mediatek,eth-mac";
		reg = <0>;
		phy-mode = "2500base-x";

		nvmem-cells = <&macaddr_factory_24 0>;
		nvmem-cell-names = "mac-address";
		fixed-link {
			speed = <2500>;
			full-duplex;
			pause;
		};
	};

	gmac1: mac@1 {
		compatible = "mediatek,eth-mac";
		reg = <1>;
		phy-mode = "gmii";
		phy-handle = <&int_gbe_phy>;

		nvmem-cells = <&macaddr_factory_2a 0>;
		nvmem-cell-names = "mac-address";
	};
};

&mdio_bus {
	switch: switch@1f {
		compatible = "mediatek,mt7531";
		reg = <31>;
		reset-gpios = <&pio 39 GPIO_ACTIVE_HIGH>;
		interrupt-controller;
		#interrupt-cells = <1>;
		interrupt-parent = <&pio>;
		interrupts = <38 IRQ_TYPE_LEVEL_HIGH>;
	};
};

&switch {
	ports {
		#address-cells = <1>;
		#size-cells = <0>;

		port@0 {
			reg = <0>;
			label = "lan3";
		};

		port@1 {
			reg = <1>;
			label = "lan2";
		};

		port@2 {
			reg = <2>;
			label = "lan1";
		};

		port@6 {
			reg = <6>;
			ethernet = <&gmac0>;
			phy-mode = "2500base-x";

			fixed-link {
				speed = <2500>;
				full-duplex;
				pause;
			};
		};
	};
};

&pio {
	mmc0_pins_default: mmc0-pins-default {
		mux {
			function = "flash";
			groups = "emmc_45";
		};
	};

	mmc0_pins_uhs: mmc0-pins-uhs {
		mux {
			function = "flash";
			groups = "emmc_45";
		};
	};
};

&uart0 {
	status = "okay";
};

&usb_phy {
	status = "okay";
};

&watchdog {
	status = "okay";
};

&xhci {
	status = "okay";
};
DTSEOF
echo "✅ 已写入设备树：$DTS_FILE"

# ---------- 2. 在 filogic.mk 中新增设备 profile ----------
if ! grep -qE "^define Device/cmcc_xr30-emmc$" "$MK_FILE"; then
    python3 - "$MK_FILE" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()

anchor = "TARGET_DEVICES += cmcc_rax3000m-emmc-mtk\n"
if anchor not in s:
    print("❌ filogic.mk 中未找到锚点 TARGET_DEVICES += cmcc_rax3000m-emmc-mtk")
    sys.exit(1)

block = """
define Device/cmcc_xr30-emmc
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := XR30 EMMC
  DEVICE_VARIANT := (MTK layout)
  DEVICE_DTS := mt7981b-cmcc-xr30-emmc
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-usb3 f2fsck mkf2fs
  SUPPORTED_DEVICES += cmcc,xr30-emmc cmcc,rax3000m-emmc
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \\
\tfit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += cmcc_xr30-emmc
"""

s = s.replace(anchor, anchor + block, 1)
open(p, 'w', encoding='utf-8').write(s)
print("✅ filogic.mk 已新增 cmcc_xr30-emmc 设备")
PYEOF
    if [ $? -ne 0 ]; then
        echo "❌ 新增 XR30 eMMC 设备 profile 失败，终止编译！"
        exit 1
    fi
else
    echo "ℹ️ filogic.mk 中已存在 cmcc_xr30-emmc，跳过"
fi

# ---------- 3. mtk-smp：让 board_name 命中 MT7981 硬件加速分组 ----------
if [ -f "$SMP_FILE" ]; then
    if ! grep -q "cmcc,xr30" "$SMP_FILE"; then
        python3 - "$SMP_FILE" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = "\t*rax3000m* |\\\n"
if old not in s:
    print("ℹ️ smp.sh 中未找到 *rax3000m* 锚点，跳过")
    sys.exit(0)
s = s.replace(old, old + "\tcmcc,xr30* |\\\n", 1)
open(p, 'w', encoding='utf-8').write(s)
print("✅ smp.sh 已加入 cmcc,xr30* 到 MT7981 分组")
PYEOF
    fi
else
    echo "ℹ️ 未找到 $SMP_FILE，跳过 smp.sh 适配（不影响编译）"
fi

# ---------- 4. uboot-envtools：让 fw_printenv 识别新机型（eMMC） ----------
if [ -f "$UBOOTENV_FILE" ]; then
    if ! grep -q "cmcc,xr30" "$UBOOTENV_FILE"; then
        python3 - "$UBOOTENV_FILE" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = "cmcc,rax3000m-emmc |\\\n"
if old not in s:
    print("ℹ️ ubootenv 中未找到 cmcc,rax3000m-emmc 锚点，跳过")
    sys.exit(0)
s = s.replace(old, "cmcc,xr30-emmc* |\\\n" + old, 1)
open(p, 'w', encoding='utf-8').write(s)
print("✅ uboot-envtools 已加入 cmcc,xr30-emmc*")
PYEOF
    fi
else
    echo "ℹ️ 未找到 $UBOOTENV_FILE，跳过 uboot-envtools 适配（不影响编译）"
fi

echo "✅ diy-part1.sh 执行完成"