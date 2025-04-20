#!/bin/bash
set -e

# 📌 默认变量
BUILD_DIR="$HOME/Downloads/openwrt-24.10"
OUTPUT_BASE="$HOME/Downloads/firmware"
LOCAL_FEED_DIR="$HOME/Downloads/package"
FEED_NAME="mypackages"

cd "$BUILD_DIR"

# 🧼 清理旧 .config
cleanup_config() {
	echo "🧹 清理旧的 .config 配置..."

	if [ -e .config ]; then
		if [ -L .config ]; then
			echo "⚠️ 检测到 .config 是符号链接，解除链接..."
			unlink .config || { echo "❌ 无法解除符号链接 .config"; exit 1; }
		elif [ -f .config ]; then
			rm -f .config || { echo "❌ 无法删除 .config 文件"; exit 1; }
		else
			echo "⚠️ .config 存在但不是普通文件，类型未知"
			ls -l .config
			exit 1
		fi
	else
		echo "ℹ️ 无需删除，.config 不存在"
	fi
}

# 📥 选择设备
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

# 🏷️ 切换 Git tag
select_git_tag() {
	GIT_TAG=$(whiptail --title "选择 OpenWrt 版本" --menu \
	"请选择要编译的 OpenWrt Git Tag：" 12 60 2 \
	"v24.10.0" "稳定版 v24.10.0" \
	"v24.10.1" "最新版 v24.10.1" 3>&1 1>&2 2>&3)

	echo "🔀 切换到 Git tag: $GIT_TAG"

	# ✋ 保护 build.sh
	cp build.sh /tmp/build.sh.bak

	# 先清理再切换分支
	git reset --hard
	git clean -xfd
	git checkout "$GIT_TAG" || {
		echo "❌ Git tag 切换失败"
		mv /tmp/build.sh.bak build.sh
		exit 1
	}

	# 还原 build.sh
	mv /tmp/build.sh.bak build.sh
}

# 🧠 设置 VERMAGIC
set_vermagic() {
	case "$GIT_TAG" in
		v24.10.0)
			case "$SUBTARGET" in
				ipq40xx)   VERMAGIC="60aeaf7e722ca0f86e06f61157755da3" ;;
				ipq807x)   VERMAGIC="fe73d0be6a246a6dcf1bbde8cd8b0d43" ;;
			esac
			;;
		v24.10.1)
			case "$SUBTARGET" in
				ipq40xx)   VERMAGIC="86a3ff6dadb6f11ea15032190af7b3de" ;;
				ipq807x)   VERMAGIC="ec8e3bd6f8a293b830bfa56c2df1a1d9" ;;
			esac
			;;
		*)
			echo "❌ 未知 tag，无法设置 vermagic"
			exit 1
			;;
	esac
}

# 💡 打印编译参数
show_summary() {
	echo ""
	echo "📋 编译参数："
	echo "📦 设备：$DEVICE"
	echo "🎯 TARGET：$TARGET"
	echo "📍 SUBTARGET：$SUBTARGET"
	echo "🏷️  Git Tag：$GIT_TAG"
	echo "🔑 VERMAGIC：$VERMAGIC"
	echo "🌐 默认 IP：$IPADDR"
	echo "📂 输出目录：$OUTPUT_DIR"
	echo ""
}

# 📁 设置输出路径
set_output_dir() {
	OUTPUT_DIR="$OUTPUT_BASE/$DEVICE"
}

# 🛠️ patch vermagic
patch_vermagic() {
	echo "$VERMAGIC" > vermagic
	sed -i '/\.vermagic/d' include/kernel-defaults.mk
	sed -i "/^define Build\/kernel/a\\\
\tcp \$(TOPDIR)/vermagic \$(LINUX_DIR)/.vermagic" include/kernel-defaults.mk
}

# 🌐 patch 默认 IP
patch_config_generate() {
	local f="package/base-files/files/bin/config_generate"

	# Remove any previously inserted lan lines
	sed -i '/lan) ipad=.*192\.88\.[0-9]\{1,3\}\.[0-9]\{1,3\}/d' "$f"

	# Insert new lan IP definition only once
	sed -i "/case \"\\\$1\" in/a\\
\\\t\\\tlan) ipad=\${ipaddr:-\"$IPADDR\"} ;;\
" "$f"
}

# 🕒 patch 默认时区
patch_timezone() {
	local f="package/base-files/files/bin/config_generate"
	sed -i "/set system.@system\[-1\].timezone/d" "$f"
	sed -i "/set system.@system\[-1\].hostname/a\\
\\\t\tset system.@system[-1].timezone='CST-8'\\
\\\t\tset system.@system[-1].zonename='Asia/Shanghai'" "$f"
}

# 🧼 清理上次构建
cleanup_previous_build() {
	echo "🧹 执行 Git 清理，保护关键文件..."

	# 暂存 build.sh 和 configs 目录
	mv build.sh ../build.sh.bak
	cp -r configs ../configs.bak

	# 重置源码，仅清理工作区
	git reset --hard
	git clean -fd -e build.sh -e configs/

	# 恢复 build.sh 和 configs
	mv ../build.sh.bak build.sh
	mv ../configs.bak configs

	chmod +x build.sh
	echo "✅ 清理完成，build.sh 和 configs/ 已安全保留"
}

# ⚙️ 准备配置
prepare_config() {
	cp "configs/${DEVICE}.config" .config
	sed -i '/CONFIG_TARGET_ROOTFS_DIR/d' .config
	echo "CONFIG_TARGET_ROOTFS_DIR=\"$OUTPUT_DIR\"" >> .config
	make defconfig
}

# 🧩 设置本地 feed
setup_local_feed() {
	grep -q "$FEED_NAME" feeds.conf.default || {
		echo "src-link $FEED_NAME $LOCAL_FEED_DIR" >> feeds.conf.default
	}
	./scripts/feeds update -a
	./scripts/feeds install -a
}

# 🔨 编译固件
build_firmware() {
	make -j$(nproc)
}

# 📦 拷贝输出
copy_all_output() {
	mkdir -p "$OUTPUT_DIR"
	rsync -a bin/targets/"$TARGET"/"$SUBTARGET"/ "$OUTPUT_DIR/targets/"
	rsync -a bin/packages/"$ARCH_PACKAGES"/ "$OUTPUT_DIR/packages/"
}

# ✅ 完成摘要
final_summary() {
	echo ""
	echo "✅ 编译完成"
	echo "📁 输出目录：$OUTPUT_DIR"
	echo "📦 所有文件已打包拷贝完毕"
	echo ""
	echo "🔁 编译信息如下："
	show_summary
}

# 🚀 主流程
cleanup_config
select_git_tag
select_device
set_vermagic
set_output_dir
patch_vermagic
patch_config_generate
patch_timezone
cleanup_previous_build
prepare_config
setup_local_feed
build_firmware
copy_all_output
final_summary
