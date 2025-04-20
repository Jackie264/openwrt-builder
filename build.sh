#!/bin/bash
set -e

# 📌 默认变量
BUILD_DIR="$HOME/Downloads/openwrt-24.10"
OUTPUT_BASE="$HOME/Downloads/firmware"
LOCAL_FEED_DIR="$HOME/Downloads/package"
FEED_NAME="mypackages"

cleanup_config() {
	rm -f .config
}

select_git_tag() {
	GIT_TAG=$(whiptail --title "OpenWrt 版本选择" --radiolist \
		"请选择要编译的 OpenWrt 版本：" 10 60 2 \
		"v24.10.0" "旧版本" ON \
		"v24.10.1" "最新版本" OFF 3>&1 1>&2 2>&3)

	cd "$BUILD_DIR"
	git checkout "$GIT_TAG"
}

select_device() {
	DEVICE=$(whiptail --title "OpenWrt 设备选择" --radiolist \
		"请选择要编译的设备：" 15 60 2 \
		"mx5300"  "Linksys MX5300 (IPQ807x)" ON \
		"whw03v2" "Linksys WHW03 V2 (IPQ40xx)" OFF 3>&1 1>&2 2>&3)

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

set_vermagic() {
	case "$GIT_TAG" in
		v24.10.0)
			case "$SUBTARGET" in
				generic)   VERMAGIC="60aeaf7e722ca0f86e06f61157755da3" ;;
				ipq807x)   VERMAGIC="fe73d0be6a246a6dcf1bbde8cd8b0d43" ;;
			esac
			;;
		v24.10.1)
			case "$SUBTARGET" in
				generic)   VERMAGIC="86a3ff6dadb6f11ea15032190af7b3de" ;;
				ipq807x)   VERMAGIC="ec8e3bd6f8a293b830bfa56c2df1a1d9" ;;
			esac
			;;
		*)
			echo "❌ 未知 tag: $GIT_TAG"
			exit 1
			;;
	esac
}

set_output_dir() {
	OUTPUT_DIR="$OUTPUT_BASE/$DEVICE"
	mkdir -p "$OUTPUT_DIR"
}

show_summary() {
	echo -e "\n📦 编译配置如下："
	echo "🔹 设备:       $DEVICE"
	echo "🔹 TAG:        $GIT_TAG"
	echo "🔹 Target:     $TARGET"
	echo "🔹 Subtarget:  $SUBTARGET"
	echo "🔹 Arch:       $ARCH_PACKAGES"
	echo "🔹 IP 地址:    $IPADDR"
	echo "🔹 VERMAGIC:   $VERMAGIC"
	echo "🔹 输出路径:   $OUTPUT_DIR"
	sleep 2
}

patch_vermagic() {
	local f="include/kernel-defaults.mk"
	if grep -q 'grep.*\.vermagic' "$f"; then
		sed -i '/grep.*\.vermagic/ s/^/#/' "$f"
		sed -i "/#.*\.vermagic/ a\\\t\tcp \$(TOPDIR)/vermagic \$(LINUX_DIR)/.vermagic" "$f"
		echo "$VERMAGIC" > vermagic
	else
		echo "❌ Failed to patch vermagic: target line not found"
	fi
}

patch_config_generate() {
	local f="package/base-files/files/bin/config_generate"
	sed -i '/lan) ipad=.*192\.168\.1\.1/d' "$f"
	sed -i "/case \"\\\$1\" in/a\\\n\t\t\tlan) ipad=\${ipaddr:-\"$IPADDR\"} ;;" "$f"
}

patch_timezone() {
	local f="package/base-files/files/bin/config_generate"
	sed -i "/set system.@system\[-1\].timezone=.*/d" "$f"
	sed -i "/set system.@system\[-1\].zonename=.*/d" "$f"
	sed -i "/set system.@system\[-1\].hostname=.*/a\\\n\t\t\tset system.@system[-1].timezone='CST-8'\\\n\t\t\tset system.@system[-1].zonename='Asia/Shanghai'" "$f"
}

cleanup_previous_build() {
	make dirclean
}

prepare_config() {
	cp "configs/${DEVICE}.config" .config
	sed -i "/CONFIG_TARGET_ROOTFS_DIR/d" .config
	echo "CONFIG_TARGET_ROOTFS_DIR=\"$OUTPUT_DIR\"" >> .config
	make defconfig
}

setup_local_feed() {
	echo "src-link $FEED_NAME $LOCAL_FEED_DIR" >> feeds.conf.default
	./scripts/feeds update -a
	./scripts/feeds install -a
}

build_firmware() {
	make -j$(nproc)
}

copy_all_output() {
	rsync -a "bin/targets/$TARGET/$SUBTARGET/" "$OUTPUT_DIR/targets/"
	rsync -a "bin/packages/$ARCH_PACKAGES/" "$OUTPUT_DIR/packages/"
}

final_summary() {
	echo -e "\n✅ 编译完成，固件输出路径：$OUTPUT_DIR"
}

cleanup_config
select_git_tag
select_device
set_vermagic
set_output_dir
show_summary
patch_vermagic
patch_config_generate
patch_timezone
cleanup_previous_build
prepare_config
setup_local_feed
build_firmware
copy_all_output
final_summary
