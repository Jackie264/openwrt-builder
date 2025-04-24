#!/bin/bash

set -e

BUILD_DIR="$HOME/Downloads/openwrt-24.10"
OUTPUT_BASE="$HOME/Downloads/firmware"
CONFIG_DIR="$HOME/Downloads/configs"
BACKUP_DIR="$HOME/Downloads/backup"
LOCAL_FEED_DIR="$HOME/Downloads/package"
FEED_NAME="mypackages"
MYFEED_URL="feeds.onenas.space"

DEVICE=""
OUTPUT_DIR=""
ARCH_PACKAGES=""
TARGET=""
SUBTARGET=""
GIT_TAG=""

BACKUP_LIST=(
	./include/kernel-defaults.mk
	./package/base-files/files/bin/config_generate
	./feeds.conf.default
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
	echo "🧩 Applying all patch files for $DEVICE..."
 	cp "$CONFIG_DIR/config.$DEVICE" ./.config
	cp "$CONFIG_DIR/vermagic.$DEVICE" ./vermagic
	cp "$CONFIG_DIR/config_generate.$DEVICE" ./package/base-files/files/bin/config_generate
 	cp "$CONFIG_DIR/kernel-defaults.mk" ./include/kernel-defaults.mk
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
	local base_device
	base_device=$(whiptail --title "Select Device" --menu "Choose a device to build:" 15 50 3 \
		"mx5300" "Linksys MX5300 (IPQ807x)" \
		"whw03v2" "Linksys WHW03 v2 (IPQ40xx)" \
		3>&1 1>&2 2>&3) || exit 1
  
	case "$base_device" in
		mx5300)
			DEVICE="mx5300"
			;;

		whw03v2)
			local sub_scene
			sub_scene=$(whiptail --title "WHW03V2 Configuration" --menu "Select deployment profile:" 12 50 2 \
				"home"   "Home network" \
				"office" "Office network" \
				3>&1 1>&2 2>&3) || exit 1

			DEVICE="$sub_scene.whw03v2"
			;;

		*)
			echo "Invalid selection"
			exit 1
			;;
	esac
}

clean_source_tree() {
	echo "🧹 Cleaning up old build artifacts..."
	if [ -f "$BUILD_DIR/Makefile" ]; then
		cd "$BUILD_DIR" || exit 1
		make clean
	else
		echo "❌ Makefile not found in $BUILD_DIR, cannot clean!"
		exit 1
	fi
}

make_output_folder() {
	echo "📁 Making output folder..."
	DATE_TAG=$(date +"%Y%m%d_%H%M")
	OUTPUT_DIR="$OUTPUT_BASE/$DEVICE/$DATE_TAG"
	mkdir -p "$OUTPUT_DIR"

 	LINK_PATH="$OUTPUT_BASE/$DEVICE/latest"
	ln -sfn "$DATE_TAG" "$LINK_PATH"

	if [ -L "$LINK_PATH" ]; then
		echo "🔗 'latest' symlink created → $LINK_PATH → $DATE_TAG"
	else
		echo "❌ Failed to create 'latest' symlink at $LINK_PATH"
	fi
}

prepare_config() {
	echo "📦 Setting ROOTFS output dir..."
	sed -i "/^CONFIG_TARGET_ROOTFS_DIR=.*/d" .config
	echo "CONFIG_TARGET_ROOTFS_DIR=\"$OUTPUT_DIR\"" >> .config
}

detect_target_info() {
	echo "🔍 Detecting target info..."

	local config_file=".config"

	TARGET=$(grep -oP '^CONFIG_TARGET_BOARD="\K[^"]+' "$config_file")
	SUBTARGET=$(grep -oP '^CONFIG_TARGET_SUBTARGET="\K[^"]+' "$config_file")
	ARCH_PACKAGES=$(grep -oP '^CONFIG_TARGET_ARCH_PACKAGES="\K[^"]+' "$config_file")

	if [[ -z "$TARGET" || -z "$SUBTARGET" || -z "$ARCH_PACKAGES" ]]; then
		echo "❌ Failed to detect TARGET, SUBTARGET, or ARCH_PACKAGES"
		exit 1
	fi

	GIT_TAG=$(git describe --tags --always 2>/dev/null || echo "unknown")
 
	echo "📦 GIT TAG=$GIT_TAG TARGET=$TARGET | SUBTARGET=$SUBTARGET | ARCH=$ARCH_PACKAGES"
}

generate_customfeeds_conf() {
	echo "📝 Generating customfeeds.conf for $DEVICE..."

	cat > package/system/opkg/files/customfeeds.conf <<EOF
src/gz my_kmod https://$MYFEED_URL/$DEVICE/latest/targets/packages
src/gz my_packages https://$MYFEED_URL/$DEVICE/latest/packages/mypackages
EOF
}

target_summary() {
	echo ""
	echo "✅ To build firmware for: $DEVICE"
	echo "📁 Firmware will save to: $OUTPUT_DIR"
	echo "📦 Target:                $TARGET"
	echo "📦 Subtarget:             $SUBTARGET"
	echo "📦 Packages arch:         $ARCH_PACKAGES"
 	echo "🔖 Git Tag:               $GIT_TAG"
	echo ""
 	sleep 2
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
	rsync -a bin/targets/"$TARGET"/"$SUBTARGET"/ "$OUTPUT_DIR/targets/"
	rsync -a bin/packages/"$ARCH_PACKAGES"/ "$OUTPUT_DIR/packages/"
}

final_summary() {
	echo ""
	echo "✅ Build completed for $DEVICE"
	echo "📁 Firmware saved to:  $OUTPUT_DIR"
	echo "📦 Target:             $TARGET"
	echo "📦 Subtarget:          $SUBTARGET"
	echo "📦 Packages arch:      $ARCH_PACKAGES"
 	echo "🔖 Git Tag:            $GIT_TAG"
	echo ""
	sleep 5
}

main() {
	cd "$BUILD_DIR"
	trap restore_original_files EXIT

	select_device
	backup_original_files
	clean_source_tree
	patch_device_files
	setup_local_feed
 	make_output_folder
	prepare_config
	detect_target_info
	generate_customfeeds_conf
 	target_summary
	build_firmware
	copy_all_output
	final_summary
}

main "$@"
