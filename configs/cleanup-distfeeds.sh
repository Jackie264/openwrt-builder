#!/bin/sh

DISTFEEDS="/etc/opkg/distfeeds.conf"
UNWANTED_LINE_PATTERN='src\/gz openwrt_mypackages'

if [ -f "$DISTFEEDS" ]; then
    if grep -q "src/gz openwrt_mypackages" "$DISTFEEDS"; then
        sed -i "/$UNWANTED_LINE_PATTERN/d" "$DISTFEEDS"
        if [ $? -eq 0 ]; then
            logger "Openwrt firstboot cleanup: Successfully removed '$UNWANTED_LINE_PATTERN' from $DISTFEEDS (via sed)."
        else
            logger "Openwrt firstboot cleanup: FAILED to remove '$UNWANTED_LINE_PATTERN' from $DISTFEEDS (sed failed)."
        fi
    else
        logger "Openwrt firstboot cleanup: '$UNWANTED_LINE_PATTERN' not found in $DISTFEEDS (may have been removed previously or pattern is wrong)."
    fi
else
    logger "Openwrt firstboot cleanup: $DISTFEEDS not found!"
fi

exit 0
