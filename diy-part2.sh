#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# 更新golang包
golangdir="feeds/packages/lang/golang"
rm -rf "$golangdir"
mkdir -p "$golangdir"
GIT_CLONE_OUTPUT=$(git clone https://github.com/sbwml/packages_lang_golang -b 24.x "$golangdir" 2>&1)
CLONE_EXIT_CODE=$?
if [ $CLONE_EXIT_CODE -eq 0 ]; then
    echo -e "✅ golang 包更新成功"
else
    echo -e "❌ golang 包更新失败：$GIT_CLONE_OUTPUT"
    exit 1
fi
# 修改插件名字
# 参数1: 原名称
# 参数2: 新名称
update_name(){  
    local old_name=$1  
    local new_name=$2  
    if grep -r "$old_name" . > /dev/null; then  
        echo -e "✅ 找到 $old_name，开始替换为 $new_name"  
        grep -rl "$old_name" . | xargs -r sed -i "s?$old_name?$new_name?g"  
    else  
        echo -e "ℹ️ 未找到 $old_name，跳过替换"  
    fi  
}
# 替换插件名字
#update_name "终端" "TTYD"
#update_name "TTYD 终端" "TTYD"
#update_name "网络存储" "NAS"
update_name "实时流量监测" "流量监测"
#update_name "KMS 服务器" "KMS"
update_name "USB 打印服务器" "打印服务"
update_name "Web 管理" "Web管理"
update_name "管理权" "账号管理"
#update_name "带宽监控" "监控"

# 解决 libxcrypt 因 -Werror=format-nonliteral 导致的编译错误
LIBXCRYPT_MAKEFILE="feeds/packages/libs/libxcrypt/Makefile"
if [ -f "$LIBXCRYPT_MAKEFILE" ]; then
    sed -i '/CFLAGS="\$(TARGET_CFLAGS) -Wno-format-nonliteral"/d' "$LIBXCRYPT_MAKEFILE"
    # 向 CONFIGURE_ARGS 中注入 CFLAGS，禁用格式非字面量警告
    sed -i '/CONFIGURE_ARGS +=/a \	CFLAGS="\$(TARGET_CFLAGS) -Wno-format-nonliteral" \\' "$LIBXCRYPT_MAKEFILE"
    if grep -q 'CFLAGS="\$(TARGET_CFLAGS) -Wno-format-nonliteral"' "$LIBXCRYPT_MAKEFILE"; then
        echo "✅ 设置libxcrypt编译参数为忽略警告"
    else
        echo "❌ 设置libxcrypt编译参数失败" >&2
        exit 1
    fi
else
    echo "ℹ️ 未找到 libxcrypt 的 Makefile，跳过修改"
fi

# 解决 quickstart 插件编译提示不支持压缩
if [ -f "package/feeds/nas_luci/luci-app-quickstart/Makefile" ]; then
    # 修正路径，从nas_luci源中查找该插件
    sed -i 's/DEPENDS:=+luci-base/DEPENDS:=+luci-base\n    NO_MINIFY=1/' "package/feeds/nas_luci/luci-app-quickstart/Makefile"
    echo "✅ 成功修改 quickstart 插件配置"
else
    echo "ℹ️ 未找到 quickstart 插件的 Makefile，跳过修改"
fi

# 验证配置文件是否存在
if [ -f ".config" ]; then
    echo "✅ .config文件配置行数: $(wc -l .config | awk '{print $1}')"
else
    echo "ℹ️ 未找到.config文件" >&2
    exit 1
fi

# ============================================================
# 强制启用「从外网连回家」所需的配置
#
# 背景：仓库根目录的 .config 是 348KB 的完整配置，直接改容易被后续
# 手工同步或 make defconfig 覆盖。这里在编译前统一兜一遍，保证每次
# 构建出来的固件一定带 WireGuard 服务端 + DDNS + ZeroTier 兜底。
#
# 之前漏掉的正是这几项：只开了 kmod-wireguard（内核模块），却没开
# wireguard-tools（没有 wg 命令）和 luci-proto-wireguard（网页面板里
# 根本看不到 WireGuard 接口），等于内核支持是空的。
# ============================================================
VPN_CFG="
CONFIG_PACKAGE_kmod-wireguard
CONFIG_PACKAGE_wireguard-tools
CONFIG_PACKAGE_luci-proto-wireguard
CONFIG_PACKAGE_rpcd-mod-wireguard
CONFIG_PACKAGE_luci-lib-uqr
CONFIG_PACKAGE_qrencode
CONFIG_PACKAGE_kmod-tun
CONFIG_PACKAGE_luci-app-ddns
CONFIG_PACKAGE_ddns-scripts
CONFIG_PACKAGE_ddns-scripts-services
CONFIG_PACKAGE_zerotier
CONFIG_PACKAGE_luci-app-zerotier
"
for _k in $VPN_CFG; do
    if grep -q "^${_k}=y$" .config; then
        echo "✅ 已启用：${_k}"
    elif grep -q "^# ${_k} is not set$" .config; then
        sed -i "s|^# ${_k} is not set\$|${_k}=y|" .config
        if grep -q "^${_k}=y$" .config; then
            echo "✅ 已启用（原为未设置）：${_k}"
        else
            echo "❌ 启用失败：${_k}" >&2
            exit 1
        fi
    else
        echo "⚠️  .config 中没有 ${_k} 条目，追加" >&2
        echo "${_k}=y" >> .config
    fi
done

# ============================================================
# 远程访问（WireGuard / DDNS / ZeroTier）关键包校验
#
# 为什么要有这一步：make defconfig 遇到 feeds 里不存在的 PACKAGE 符号时
# 不会报错，而是静默把 .config 里的 =y 抹成 not set，最后编出一个
# 「看着正常、实际没有 VPN」的固件，非常难排查。宁可在编译早期直接失败。
# ============================================================
NEED_PKGS="wireguard-tools luci-proto-wireguard luci-app-ddns ddns-scripts qrencode zerotier luci-app-zerotier"
PKGNAMES_FILE="$(mktemp)"
# 一次性把所有 Makefile 的 PKG_NAME 抓出来，避免每个包都全盘 find
find package feeds -name Makefile -type f -exec grep -h '^PKG_NAME[[:space:]]*:=' {} + 2>/dev/null \
    | sed 's/^PKG_NAME[[:space:]]*:=[[:space:]]*//' | tr -d ' \r' | sort -u > "$PKGNAMES_FILE"
MISSING=""
for _p in $NEED_PKGS; do
    if ! grep -qx "$_p" "$PKGNAMES_FILE"; then
        MISSING="$MISSING $_p"
    fi
done
rm -f "$PKGNAMES_FILE"
if [ -n "$MISSING" ]; then
    echo "❌ 以下包在当前 feeds 中不存在，构建中止（否则会静默丢掉这些功能）：$MISSING" >&2
    exit 1
fi
echo "✅ 远程访问关键包校验通过：$NEED_PKGS"

# ============================================================
# 修复 files/ 下脚本的可执行权限
# GitHub 网页/API 提交的文件默认 644，而 uci-defaults、hotplug、/usr/bin
# 下的脚本必须是可执行位，否则开机根本不会被调用（而且很难发现）。
# ============================================================
for _f in files/etc/uci-defaults/* files/etc/hotplug.d/iface/* files/usr/bin/* files/root/*.sh; do
    [ -f "$_f" ] && chmod +x "$_f" && echo "✅ 已加可执行位：$_f"
done 2>/dev/null || true

# 显示最终配置文件信息
echo "✅ diy-part2.sh 执行完成"
