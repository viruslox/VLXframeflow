#!/bin/bash

PROFILE_NAME=$1
# Sort all interfaces, pickup only the first wi-fi interface.
WIFI_IF=$(ls /sys/class/net/ | while read iface; do [ -d "/sys/class/net/$iface/wireless" ] && echo $iface && break; done)

## Validate input args
PROFILE_PATH="/etc/systemd/network/profiles/$PROFILE_NAME"
if [ -z "$PROFILE_NAME" ] || [ ! -d "$PROFILE_PATH" ]; then
    echo "[ERR] Please give a valid profile name"
    exit 1
fi

systemctl stop hostapd
systemctl stop wpa_supplicant@$WIFI_IF.service
systemctl disable hostapd
systemctl disable wpa_supplicant@$WIFI_IF.service

# Clean systemd network settings
rm -f /etc/systemd/network/*.network /etc/systemd/network/*.netdev

# Copy profiles settings
cp "$PROFILE_PATH"/* /etc/systemd/network/

systemctl restart systemd-networkd

if [ "$PROFILE_NAME" = "normal" ]; then
    sleep 2
    systemctl enable wpa_supplicant@$WIFI_IF.service
    systemctl start wpa_supplicant@$WIFI_IF.service
elif [ "$PROFILE_NAME" = "ap-bonding" ]; then
    sleep 2 
    systemctl enable hostapd
    systemctl start hostapd
fi

echo "$PROFILE_NAME Enabled"

exit 0
