#!/bin/bash

set -e

BUILD_DIR="$HOME/Downloads/openwrt-24.10"
OUTPUT_BASE="$HOME/Downloads/firmware"
CONFIG_DIR="$HOME/Downloads/configs"
BACKUP_DIR="$HOME/Downloads/backup"
LOCAL_FEED_DIR="$HOME/Downloads/package"
FEED_NAME="mypackages"
DATE_TAG=$(date +"%Y%m%d_%H%M")

DEVICE=""
OUTPUT_DIR=""
ARCH_PACKAGES=""
TARGET=""
SUBTARGET=""

BACKUP_LIST=(
	include/kernel-defaults.mk
	package/base-files/files/bin/config_generate
	feeds.conf.default
)

# Clean up any temporary patch
restore_original_files() {
	echo "🔁 Restoring original files..."
	for file in "${BACKUP_LIST[@]}"; do
		base_name=$(basename "$file")
		[ -f "$BACKUP_DIR/$base_name" ] && cp "$BACKUP_DIR/$base_name" "$file"
	done
}

backup_original_files() {
	echo "📦 Backing up original files..."
	mkdir -p "$BACKUP_DIR"
	for file in "${BACKUP_LIST[@]}"; do
		base_name=$(basename "$file")
		[ -f "$file" ] && cp "$file" "$BACKUP_DIR/$base_name"
	done
}

patch_device_files() {
	echo "🧩 Applying device-specific files for $DEVICE..."
	cp "$CONFIG_DIR/vermagic.$DEVICE" ./vermagic
	cp "$CONFIG_DIR/config_generate.$DEVICE" package/base-files/files/bin/config_generate
}

patch_common_files() {
	echo "🧩 Patching common files..."
	cp "$CONFIG_DIR/kernel-defaults.mk" include/kernel-defaults.mk
}

setup_local_feed() {
	echo "📦 Setting up local feed..."
	if ! grep -q "$FEED_NAME" feeds.conf.default; then
		echo "src-link $FEED_NAME $LOCAL_FEED_DIR" >> feeds.conf.default
	fi
	./scripts/feeds update -a
	./scripts/feeds install -a
}

select_device() {
	DEVICE=$(whiptail --title "Select Device" --menu "Choose a device to build:" 15 50 3 \
		"mx5300" "Linksys MX5300 (IPQ807x)" \
		"whw03v2" "Linksys WHW03 v2 (IPQ40xx)" \
		3>&1 1>&2 2>&3) || exit 1
}

make_clean() {
	echo "🧹 Cleanning old bin folder..."
	make clean
}

prepare_config() {
	cp "$CONFIG_DIR/$DEVICE.config" .config
	mkdir -p "$OUTPUT_BASE/$DEVICE/$DATE_TAG"
	#OUTPUT_DIR="$OUTPUT_BASE/$DEVICE"
	OUTPUT_DIR="$OUTPUT_BASE/$DEVICE/$DATE_TAG"

	# Set ROOTFS output dir
	sed -i "/^CONFIG_TARGET_ROOTFS_DIR=.*/d" .config
	echo "CONFIG_TARGET_ROOTFS_DIR=\"$OUTPUT_DIR\"" >> .config
}

detect_target_info() {
	source include/kernel-version.mk
	TARGET=$(grep CONFIG_TARGET_BOARD= .config | cut -d'"' -f2)
	SUBTARGET=$(grep CONFIG_TARGET_SUBTARGET= .config | cut -d'"' -f2)
	ARCH_PACKAGES=$(grep CONFIG_TARGET_ARCH_PACKAGES= .config | cut -d'"' -f2)
}

build_firmware() {
	echo "⚙️ Starting build for $DEVICE..."
	make defconfig
	make download -j$(nproc)
	if ! make V=s -j$(nproc); then
		echo "⚠️ Multithread build failed. Retrying with single thread..."
		make V=s -j1
	fi
}

copy_all_output() {
	echo "📤 Copying firmware and packages..."
	mkdir -p "$OUTPUT_DIR"
	rsync -a bin/targets/"$TARGET"/"$SUBTARGET"/ "$OUTPUT_DIR/targets/"
	rsync -a bin/packages/"$ARCH_PACKAGES"/ "$OUTPUT_DIR/packages/"
}

final_summary() {
	echo ""
	echo "✅ Build completed for $DEVICE"
	echo "📁 Firmware saved to: $OUTPUT_DIR"
	echo "📦 Target: $TARGET"
	echo "📦 Subtarget: $SUBTARGET"
	echo "📦 Packages arch: $ARCH_PACKAGES"
}

main() {
	cd "$BUILD_DIR"

	trap restore_original_files EXIT

	select_device
	backup_original_files
	patch_device_files
	patch_common_files
	setup_local_feed
 	make_clean
	prepare_config
	detect_target_info
	build_firmware
	copy_all_output
	final_summary
}

main "$@"
