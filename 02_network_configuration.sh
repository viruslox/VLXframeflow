#!/bin/bash

### TODO: create /etc/wpa_supplicant/wpa_supplicant-$iface.conf grabbing info from network manager or leave it empty

if [ "$EUID" -ne 0 ]; then
  echo "[ERR]: This script requires root privileges."
  exit 1
fi

NORM_PROFILE="/etc/systemd/network/profiles/normal"
AP_PROFILE="/etc/systemd/network/profiles/ap-bonding"
mkdir -p $NORM_PROFILE $AP_PROFILE

cat <<EOF > $AP_PROFILE/10-bond0.netdev
[NetDev]
Name=bond0
Kind=bond

[Bond]
Mode=active-backup
EOF

cat <<EOF > $AP_PROFILE/20-bond0.network
[Match]
Name=bond0

[Network]
DHCP=yes
EOF

## for each interface create profiles
for iface in $(ls /sys/class/net); do
    if [ "$iface" == "lo" ]; then
        continue
    fi

    if [ -d "/sys/class/net/$iface/wireless" ]; then
### wireless interfaces
cat <<EOF > $NORM_PROFILE/20-$iface.network
[Match]
Name=$iface

[Network]
DHCP=yes
WPAConfigFile=/etc/wpa_supplicant/wpa_supplicant-$iface.conf
EOF

cat <<EOF > $AP_PROFILE/40-$iface-ap.network
[Match]
Name=$iface

[Network]
Address=192.168.10.1/24
IPMasquerade=yes
DHCPServer=yes

[DHCPServer]
DNS=8.8.8.8 1.1.1.1
EOF

cat <<EOF > /etc/hostapd/hostapd.conf
interface=$iface
driver=nl80211
hw_mode=g
channel=7

ssid=VLXnetflow
wpa=2
wpa_passphrase=LaTuaPasswordSuperSegreta
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

systemctl enable wpa_supplicant@$iface.service

    else
## Ethernet and USB net interfaces
cat <<EOF > $NORM_PROFILE/10-$iface.network
[Match]
Name=$iface

[Network]
DHCP=yes
EOF

cat <<EOF > $AP_PROFILE/30-$iface-bond.network
[Match]
Name=$iface

[Network]
Bond=bond0
EOF
    fi
done


## Enable the new settings
systemctl disable NetworkManager
systemctl enable systemd-networkd
systemctl enable systemd-resolved

echo "Now You should restart to give a try - ...keep monitor and keyboard on Your arm lenght range :D"
