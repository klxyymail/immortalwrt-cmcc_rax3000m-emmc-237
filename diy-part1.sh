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
# 适配 CMCC XR30 eMMC 的 LED（红灯 pio35 / 白灯 pio34）
#
# 背景：RAX3000M eMMC 与 XR30 eMMC 硬件相同（MT7981B+512M+64G eMMC），固件可互刷，
#       唯一差异是 LED：RAX3000M 有 3 颗（绿 pio9 / 蓝 pio12 / 红 pio35），
#       XR30 只有 2 颗（白 pio34 / 红 pio35）。
#       因此红灯天然可用，白灯因固件 DTS 未定义 pio34 而完全不可控。
#
# 做法：保留 compatible = "cmcc,rax3000m-emmc" 不变（这样 02_network 中
#       "*rax3000m*" 分支仍能命中，LAN/WAN MAC 依旧从 eMMC factory 分区
#       0x24/0x2a 读取，不会出现 MAC 随机），仅替换 LED 节点与别名。
# ==========================================================================
DTS_FILE="target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc-mtk.dts"
if [ -f "$DTS_FILE" ]; then
    python3 - "$DTS_FILE" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
orig = s

# 1) 别名：运行时/升级指示灯由绿灯改为白灯
s = s.replace('led-running = &green_led;', 'led-running = &white_led;')
s = s.replace('led-upgrade = &green_led;', 'led-upgrade = &white_led;')

# 2) 只改显示型号，compatible 保持 cmcc,rax3000m-emmc 不动
s = s.replace('model = "CMCC RAX3000M eMMC (MTK UBoot)";',
              'model = "CMCC XR30 eMMC (MTK UBoot)";')

# 3) 整个 gpio-leds 节点替换为 XR30 的双色灯
new_leds = '''	gpio-leds {
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
'''
s = re.sub(r'\tgpio-leds \{.*?\n\t\};\n', new_leds, s, count=1, flags=re.S)

open(p, 'w', encoding='utf-8').write(s)

ok = ('&pio 34 GPIO_ACTIVE_LOW' in s and '&pio 35 GPIO_ACTIVE_LOW' in s
      and 'white_led' in s and 'green_led' not in s and 'pio 12' not in s)
print("✅ DTS LED 已适配 XR30 eMMC（白 pio34 / 红 pio35）" if ok
      else "❌ DTS LED 适配结果校验失败")
sys.exit(0 if ok else 1)
PYEOF
    if [ $? -ne 0 ]; then
        echo "❌ 适配 XR30 eMMC LED 失败，终止编译！"
        exit 1
    fi
else
    echo "❌ 未找到 $DTS_FILE，无法适配 XR30 eMMC LED，终止编译！"
    exit 1
fi

echo "✅ diy-part1.sh 执行完成"