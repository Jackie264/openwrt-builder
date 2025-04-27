#!/bin/sh
# /etc/uci-defaults/99-cleanup-feeds
# This script runs on first boot to remove the unwanted mypackages entry from distfeeds.conf

DISTFEEDS="/etc/opkg/distfeeds.conf"
UNWANTED_LINE_PATTERN="src/gz openwrt_mypackages"

if [ -f "$DISTFEEDS" ]; then
	if grep -q "$UNWANTED_LINE_PATTERN" "$DISTFEEDS"; then
		echo "Removing unwanted '$UNWANTED_LINE_PATTERN' entry from $DISTFEEDS"
		sed -i "/$UNWANTED_LINE_PATTERN/d" "$DISTFEEDS"
		logger "OpenWrt firstboot cleanup: Removed '$UNWANTED_LINE_PATTERN' from $DISTFEEDS"
	fi
fi

exit 0
