#!/bin/bash

set -e

# ========== 用户配置 ==========
BUILD_DIR="$HOME/Downloads/openwrt-24.10"
OUTPUT_BASE="$HOME/Downloads/firmware"
CONFIGS_DIR="$HOME/Downloads/configs"
BACKUP_DIR="$HOME/Downloads/backup"
LOCAL_FEED_DIR="$HOME/Downloads/package"
FEED_NAME="mypackages"
TAG_NAME="v24.10.1"

# ========== 交互式设备选择 ==========
select_device() {
	DEVICE=$(whiptail --title "Select Device" --menu "Choose your target device:" 15 50 4 \
		"mx5300" "Linksys MX5300 (ipq807x)" \
		"whw03v2" "Linksys WHW03 V2 (ipq40xx)" \
		3>&1 1>&2 2>&3)

	if [ $? -ne 0 ]; then
		echo "❌ Device selection cancelled."
		exit 1
	fi
}

# ========== 克隆源码 & 切换 tag ==========
clone_openwrt() {
	if [ ! -d "$BUILD_DIR" ]; then
		echo "🌐 Cloning OpenWrt..."
		git clone https://github.com/openwrt/openwrt.git "$BUILD_DIR"
	fi
	cd "$BUILD_DIR"
	git fetch
	git checkout "$TAG_NAME"
}

# ========== 本地 feed 设置 ==========
setup_local_feed() {
	if ! grep -q "$FEED_NAME" feeds.conf.default 2>/dev/null; then
		echo "src-link $FEED_NAME $LOCAL_FEED_DIR" >> feeds.conf.default
	fi
	./scripts/feeds update -a
	./scripts/feeds install -a
}

# ========== 备份并替换源码文件 ==========
backup_and_patch_files() {
	echo "📦 Backing up and patching files for $DEVICE..."
	mkdir -p "$BACKUP_DIR"

	local PATCH_LIST=("vermagic" "include/kernel-defaults.mk" "package/base-files/files/bin/config_generate")
	local BACKUP_LIST=("include/kernel-defaults.mk" "package/base-files/files/bin/config_generate")

	for file in "${BACKUP_LIST[@]}"; do
		local base_name
		base_name=$(basename "$file")
		cp "$file" "$BACKUP_DIR/$base_name"
	done

	for file in "${PATCH_LIST[@]}"; do
		local base_name
		base_name=$(basename "$file")
		local src_file="$CONFIGS_DIR/${base_name}.${DEVICE}"
		[ -f "$src_file" ] && cp "$src_file" "$file"
	done
}

# ========== 使用设备配置 ==========
prepare_config() {
	cp "$CONFIGS_DIR/${DEVICE}.config" .config
	sed -i "s|^CONFIG_TARGET_ROOTFS_DIR=.*|CONFIG_TARGET_ROOTFS_DIR=\"\$HOME/Downloads/firmware/${DEVICE}\"|" .config
	make defconfig
}

# ========== 编译固件 ==========
build_firmware() {
	echo "🚧 Building firmware..."
	if ! make -j"$(nproc)"; then
		echo "⚠️ Multi-thread build failed. Trying single-thread..."
		make -j1 V=s
	fi
}

# ========== 拷贝编译产物 ==========
copy_all_output() {
	local OUTPUT_DIR="$OUTPUT_BASE/${DEVICE}"
	mkdir -p "$OUTPUT_DIR"
	rsync -a bin/targets/*/* "$OUTPUT_DIR/targets/"
	rsync -a bin/packages/* "$OUTPUT_DIR/packages/"
}

# ========== 还原原始源码 ==========
restore_original_files() {
	echo "🧹 Restoring original source files..."
	local RESTORE_LIST=("include/kernel-defaults.mk" "package/base-files/files/bin/config_generate")
	for file in "${RESTORE_LIST[@]}"; do
		local base_name
		base_name=$(basename "$file")
		cp "$BACKUP_DIR/$base_name" "$file"
	done
}

# ========== 输出构建摘要 ==========
final_summary() {
	echo "✅ Build completed for: $DEVICE"
	echo "📁 Output directory: $OUTPUT_BASE/${DEVICE}"
	echo "🌿 Git tag used: $TAG_NAME"
}

# ========== 主流程 ==========
main() {
	select_device
	clone_openwrt
	setup_local_feed
	backup_and_patch_files
	prepare_config
	build_firmware
	copy_all_output
	final_summary
	restore_original_files
}

main
