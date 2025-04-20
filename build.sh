#!/bin/bash
set -e

# 📌 默认变量
BUILD_DIR="$HOME/Downloads/openwrt-24.10"
OUTPUT_BASE="$HOME/Downloads/firmware"
LOCAL_FEED_DIR="$HOME/Downloads/package"
FEED_NAME="mypackages"
CONFIGS_DIR="$HOME/Downloads/configs"
BACKUP_SCRIPT="$CONFIGS_DIR/build.sh"

# 📦 自动备份自身与 configs
protect_essentials() {
        echo "🛡️ 正在保护 build.sh 和 configs..."
        mkdir -p "$CONFIGS_DIR"
        cp -f "$0" "$BACKUP_SCRIPT"
}

# 🧹 清理旧配置
cleanup_config() {
        echo "🧹 清理旧的 .config 配置..."
        rm -f .config
}

# 🔀 选择 Git tag
select_git_tag() {
        GIT_TAG=$(whiptail --title "OpenWrt 版本选择" --menu \
        "请选择要切换的版本（Git tag）：" 15 60 2 \
        "v24.10.0" "使用 tag v24.10.0" \
        "v24.10.1" "使用 tag v24.10.1" 3>&1 1>&2 2>&3)

        if [ -n "$GIT_TAG" ]; then
                echo "🔀 切换到 Git tag: $GIT_TAG"
                git reset --hard HEAD
                git clean -fdx
                git checkout "$GIT_TAG" || { echo "❌ Git tag 切换失败"; exit 1; }
        fi
}

# 📱 设备选择
select_device() {
        DEVICE=$(whiptail --title "OpenWrt 设备选择" --menu \
        "请选择要编译的设备：" 15 60 2 \
        "mx5300"  "Linksys MX5300 (IPQ807x)" \
        "whw03v2" "Linksys WHW03 V2 (IPQ40xx)" 3>&1 1>&2 2>&3)

        case "$DEVICE" in
                mx5300)
                        TARGET="qualcommax"
                        SUBTARGET="ipq807x"
                        ARCH_PACKAGES="aarch64_cortex-a53"
                        IPADDR="192.88.9.53"
                        ;;
                whw03v2)
                        TARGET="ipq40xx"
                        SUBTARGET="generic"
                        ARCH_PACKAGES="arm_cortex-a7_neon-vfpv4"
                        IPADDR="192.88.9.5"
                        ;;
                *)
                        echo "❌ 无效选择"
                        exit 1
                        ;;
        esac
}

# 🧬 根据 tag 设置 vermagic
set_vermagic() {
        case "$GIT_TAG" in
                v24.10.0)
                        if [ "$SUBTARGET" = "ipq807x" ]; then
                                VERMAGIC="fe73d0be6a246a6dcf1bbde8cd8b0d43"
                        elif [ "$SUBTARGET" = "generic" ]; then
                                VERMAGIC="60aeaf7e722ca0f86e06f61157755da3"
                        fi
                        ;;
                v24.10.1)
                        if [ "$SUBTARGET" = "ipq807x" ]; then
                                VERMAGIC="ec8e3bd6a293b830bfa56c2df1a1d9"
                        elif [ "$SUBTARGET" = "generic" ]; then
                                VERMAGIC="86a3ff6dadb6f11ea15032190af7b3de"
                        fi
                        ;;
                *)
                        echo "⚠️ 未知 Git tag，无法设置 VERMAGIC"
                        exit 1
                        ;;
        esac
}

# 🖨️ 编译输出路径
set_output_dir() {
        OUTPUT_DIR="$OUTPUT_BASE/$DEVICE"
        mkdir -p "$OUTPUT_DIR"
}

# 🩹 patch vermagic
patch_vermagic() {
        sed -i '/vermagic/d' include/kernel-defaults.mk
        sed -i '/^\s*cp \$\(LINUX_DIR\)\/\.vermagic/d' include/kernel-defaults.mk
        echo "cp \$(TOPDIR)/vermagic \$(LINUX_DIR)/.vermagic" >> include/kernel-defaults.mk
        echo "$VERMAGIC" > vermagic
}

# 🩹 patch 默认管理 IP
patch_config_generate() {
        local f="package/base-files/files/bin/config_generate"
        sed -i '/lan) ipad=.*192\.168\.[0-9]\+\.[0-9]\+.*;;/d' "$f"
        sed -i "/case \"\\\$1\" in/a\\
\\\t\\\tlan) ipad=\${ipaddr:-\"$IPADDR\"} ;;\
" "$f"
}

# 🩹 patch 默认时区
patch_timezone() {
        local f="package/base-files/files/bin/config_generate"
        sed -i "/set system.@system\[-1\].timezone/d" "$f"
        sed -i "/set system.@system\[-1\].zonename/d" "$f"
        sed -i "/uci commit system/i\\
\tset system.@system[-1].timezone='CST-8'\\
\tset system.@system[-1].zonename='Asia/Shanghai'" "$f"
}

# 🧽 清理源码目录
cleanup_previous_build() {
        find . -name bin -type d -exec rm -rf {} +
        find . -name build_dir -type d -exec rm -rf {} +
        find . -name staging_dir -type d -exec rm -rf {} +
}

# ⚙️ 配置编译
prepare_config() {
        cp "$CONFIGS_DIR/${DEVICE}.config" .config
        sed -i "/CONFIG_TARGET_ROOTFS_DIR/d" .config
        echo "CONFIG_TARGET_ROOTFS_DIR=\"$OUTPUT_DIR\"" >> .config
        make defconfig
}

# 🧩 添加本地 feed
setup_local_feed() {
        echo "🧩 设置本地 feed: $FEED_NAME -> $LOCAL_FEED_DIR"

        # Check if the src-link already exists
        if grep -q "src-link $FEED_NAME $LOCAL_FEED_DIR" feeds.conf.default; then
                echo "✅ 本地 feed 已存在，跳过设置。"
        else
                echo "src-link $FEED_NAME $LOCAL_FEED_DIR" >> feeds.conf.default
                echo "✅ 已添加本地 feed 到 feeds.conf.default"
        fi

        ./scripts/feeds update -a
        ./scripts/feeds install -a
}

pre_download() {
        make download -j$(nproc)
}

# 🛠️ 编译固件
build_firmware() {
        if ! make V=s -j$(nproc); then
                echo "⚠️ 多线程编译失败，尝试使用单线程..."
                make V=s -j1
        fi
}

# 📦 拷贝固件和 IPK
copy_all_output() {
        mkdir -p "$OUTPUT_DIR"
        rsync -a bin/targets/"$TARGET"/"$SUBTARGET"/ "$OUTPUT_DIR/targets/"
        rsync -a bin/packages/"$ARCH_PACKAGES"/ "$OUTPUT_DIR/packages/"
}

# 📄 最终参数汇总
final_summary() {
        echo -e "\n📦 编译完成！参数如下："
        echo "➡️  设备:  .   $DEVICE"
        echo "➡️  当前TAG:   $GIT_TAG"
        echo "➡️  TARGET:    $TARGET"
        echo "➡️  SUBTARGET: $SUBTARGET"
        echo "➡️  ARCH:      $ARCH_PACKAGES"
        echo "➡️  IPADDR:    $IPADDR"
        echo "➡️  VERMAGIC:  $VERMAGIC"
        echo "➡️  输出目录:  $OUTPUT_DIR"
}

# 🚀 主流程
protect_essentials
cleanup_config
select_git_tag
select_device
set_vermagic
set_output_dir
patch_vermagic
patch_config_generate
patch_timezone
cleanup_previous_build
setup_local_feed
prepare_config
pre_download
build_firmware
copy_all_output
final_summary
