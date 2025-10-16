#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "[ERR]: This script requires root privileges."
  exit 1
fi

# Enable MPTCP
if ! sysctl net.mptcp.enabled &> /dev/null; then
    echo "[ERR] The running kernel does not support Multipoint TCP."
    exit 1
elif [ "$(sysctl -n net.mptcp.enabled)" -eq 0 ]; then
    echo "[WARN] MPTCP is not enabled. Enabling it now."
    sysctl -w net.mptcp.enabled=1
    echo "[OK] MPTCP enabled."
else
    echo "[OK] MPTCP is already enabled."
fi

NORM_PROFILE="/etc/systemd/network/profiles/normal"
AP_PROFILE="/etc/systemd/network/profiles/ap-bonding"
mkdir -p $NORM_PROFILE $AP_PROFILE

ufw allow 22/tcp
sed -i '/^DEFAULT_FORWARD_POLICY/c\DEFAULT_FORWARD_POLICY="ACCEPT"' /etc/default/ufw

if [ ! -f /etc/ufw/before.rules.BK ]; then
	cp -p /etc/ufw/before.rules /etc/ufw/before.rules.BK
fi

if ! grep -qF "VLXframelow NAT table rules" /etc/ufw/before.rules; then
	echo "[INFO]: Updating UFW settings with NAT rules"
	NAT_RULES=$(cat <<EOF
# VLXframelow NAT table rules
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.168.0/24 -j MASQUERADE
COMMIT
# End of VLXframeflow NAT rules
EOF
)
	echo -e "$NAT_RULES\n$(cat /etc/ufw/before.rules)" > /etc/ufw/before.rules
fi

## for each interface create profiles
INTERFACES=($(iwconfig 2>/dev/null | grep 'IEEE' | awk '{print $1}'))
if [ ${#INTERFACES[@]} -eq 0 ]; then
    echo "No wireless network interface found."
    exit 1
fi

for iface in "${INTERFACES[@]}"; do
    cat <<EOF > "$NORM_PROFILE/20-$iface.network"
[Match]
Name=$iface

[Network]
DHCP=yes
WPAConfigFile=/etc/wpa_supplicant/wpa_supplicant-$iface.conf

[Address]
MPTCPSubflow=no
EOF

    if [[ "$iface" == "${INTERFACES[0]}" ]]; then
		ufw allow in on $iface from any port 68 to any port 67 proto udp
		ufw allow in on $iface from any to any port 53
        cat <<EOF > "$AP_PROFILE/40-$iface-ap.network"
[Match]
Name=$iface
WLANMode=ap

[Network]
Address=192.168.168.1/24
IPMasquerade=yes
DHCPServer=yes

[Address]
MPTCPSubflow=no

[DHCPServer]
DNS=8.8.8.8 1.1.1.1
EOF

        cat <<EOF > /etc/hostapd/hostapd.conf
interface=$iface
driver=nl80211
hw_mode=g
channel=7
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
ssid=VLXnetflow
wpa=2
wpa_passphrase=LaTuaPasswordSuperSegreta
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOF

    WPA_CONF="/etc/wpa_supplicant/wpa_supplicant-$iface.conf"
    cp -p "$WPA_CONF" "${WPA_CONF}_$(date +%Y-%m-%d_%Hh%Mm)" 2>/dev/null

    for knownwlans in /etc/NetworkManager/system-connections/*; do
        if grep -q 'type=wifi' "$knownwlans"; then
            SSID=$(grep -oP 'ssid=\K.*' "$knownwlans")
            PSK=$(grep -oP 'psk=\K.*' "$knownwlans")

            if [ -n "$SSID" ] && [ -n "$PSK" ]; then
                echo 'network={' >> "$WPA_CONF"
                echo "    ssid=\"$SSID\"" >> "$WPA_CONF"
                echo "    psk=\"$PSK\"" >> "$WPA_CONF"
                echo '}' >> "$WPA_CONF"
            fi
        fi
    done
    
    systemctl enable "wpa_supplicant@$iface.service"
	else
	    cat <<EOF > "$AP_PROFILE/20-$iface.network"
[Match]
Name=$iface

[Network]
DHCP=yes
WPAConfigFile=/etc/wpa_supplicant/wpa_supplicant-$iface.conf

[Address]
MPTCPSubflow=no
EOF
	fi
done

cat <<'EOF' > /etc/systemd/system/hostapd.service
[Unit]
Description=Access point and authentication server for Wi-Fi and Ethernet
Documentation=man:hostapd(8)
After=network.target
ConditionFileNotEmpty=/etc/hostapd/hostapd.conf

[Service]
#Type=forking
Type=exec
#PIDFile=/run/hostapd.pid
Restart=on-failure
RestartSec=2
Environment=DAEMON_CONF=/etc/hostapd/hostapd.conf
EnvironmentFile=-/etc/default/hostapd
#ExecStart=/usr/sbin/hostapd -B -P /run/hostapd.pid $DAEMON_OPTS ${DAEMON_CONF}
ExecStart=/usr/sbin/hostapd -P /run/hostapd.pid $DAEMON_OPTS ${DAEMON_CONF}

[Install]
WantedBy=multi-user.target
EOF

## for each interface create profiles
for iface in $(ls /sys/class/net); do
    if [ "$iface" == "lo" ]; then
        continue
    elif [[ "$iface" != *bond* && ! -d "/sys/class/net/$iface/wireless" ]]; then
## Ethernet and USB net interfaces
cat <<EOF > $NORM_PROFILE/10-$iface.network
[Match]
Name=$iface

[Network]
DHCP=yes

[Address]
MPTCPSubflow=no
EOF

cat <<EOF > $AP_PROFILE/30-$iface-mptcp.network
[Match]
Name=$iface

[Network]
DHCP=yes

[Address]
MPTCPSubflow=yes

[Route]
Gateway=_dhcp4
Metric=100
EOF
    fi
done



## Enable the new settings
apt-get update
apt-get -y install mptcpd
systemctl daemon-reload
systemctl disable NetworkManager
systemctl enable systemd-networkd
systemctl enable systemd-resolved


sed -i \
-e 's/^#* *path-manager=.*/path-manager=default/' \
-e 's/^#* *load-plugins=.*/load-plugins=addr_adv/' \
-e 's/^#* *addr-flags=.*/addr-flags=subflow,signal,fullmesh/' \
/etc/mptcpd/mptcpd.conf

systemctl enable mptcp

ufw reload
ufw --force enable
echo "Now You should restart to give a try - ...keep monitor and keyboard on Your arm lenght range :D"

exit 0
