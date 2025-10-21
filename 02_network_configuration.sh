#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "[ERR]: This script requires root privileges."
  exit 1
fi

apt-get update
systemctl disable NetworkManager
apt-get -y install ufw mptcpd hostapd systemd-timesyncd networkd-dispatcher

# Enable MPTCP
if ! sysctl net.mptcp.enabled &> /dev/null; then
    echo "[ERR] The running kernel does not support Multipoint TCP."
    exit 1
elif [ "$(sysctl -n net.mptcp.enabled)" -eq 0 ]; then
    echo "[WARN] MPTCP is not enabled. Enabling it now."
    sysctl -w net.mptcp.enabled=1
	sysctl -w net.mptcp.checksum_enabled=1
    if [ ! -e /etc/sysctl.d/98-mptcp.conf ]; then
        echo "net.mptcp.enabled=1" > /etc/sysctl.d/98-mptcp.conf
		echo "net.mptcp.checksum_enabled=1" >> /etc/sysctl.d/98-mptcp.conf
    fi
    echo "[OK] MPTCP enabled."
else
    echo "[OK] MPTCP is already enabled."
fi

if [ ! -e /etc/sysctl.d/97-forwarding.conf ]; then
    echo "[INFO] Enabling IPv4 and IPv6 forwarding..."
cat <<EOF > /etc/sysctl.d/97-forwarding.conf
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
    sysctl -p /etc/sysctl.d/97-forwarding.conf
fi

NORM_PROFILE="/etc/systemd/network/profiles/normal"
AP_PROFILE="/etc/systemd/network/profiles/ap-bonding"
DISPATCHER_DIR="/etc/networkd-dispatcher/routable.d"
mkdir -p "$NORM_PROFILE" "$AP_PROFILE" "$DISPATCHER_DIR"

# Configuring Firewall (UFW)
ufw allow 22/tcp
sed -i '/^DEFAULT_FORWARD_POLICY/c\DEFAULT_FORWARD_POLICY="ACCEPT"' /etc/default/ufw
if ! grep -q 'IPV6=yes' /etc/default/ufw; then
    echo 'IPV6=yes' >> /etc/default/ufw
fi

# Backup UFW settings
if [ ! -f /etc/ufw/before.rules.BK ]; then
    cp -p /etc/ufw/before.rules /etc/ufw/before.rules.BK
fi
if [ ! -f /etc/ufw/before6.rules ]; then
    touch /etc/ufw/before6.rules
fi

# AP-mode IPv4 forwarding
if ! grep -qF "VLXframelow NAT table rules" /etc/ufw/before.rules; then
    echo "[INFO]: Updating UFW settings with NAT rules for IPv4"
    NAT_RULES=$(cat <<'EOF'
# VLXframelow NAT table rules
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.168.0/24 -j MASQUERADE
COMMIT
# End of VLXframeflow NAT rules
EOF
)
    # Prepend rules to the file
    echo -e "$NAT_RULES\n$(cat /etc/ufw/before.rules)" > /etc/ufw/before.rules
fi

# AP-mode IPv6 forwarding
if ! grep -qF "VLXframelow IPv6 forwarding rules" /etc/ufw/before6.rules; then
    echo "[INFO]: Updating UFW settings with forwarding rules for IPv6"
    NAT6_RULES=$(cat <<'EOF'
# VLXframelow IPv6 forwarding rules
*filter
:ufw6-forward - [0:0]
:ufw6-before-forward - [0:0]
-A ufw6-before-forward -p icmpv6 --icmpv6-type neighbor-solicitation -j ACCEPT
-A ufw6-before-forward -p icmpv6 --icmpv6-type neighbor-advertisement -j ACCEPT
-A ufw6-before-forward -p icmpv6 --icmpv6-type router-solicitation -j ACCEPT
-A ufw6-before-forward -p icmpv6 --icmpv6-type router-advertisement -j ACCEPT
-A ufw6-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
COMMIT
# End of VLXframeflow IPv6 rules
EOF
)
    echo -e "$NAT6_RULES\n$(cat /etc/ufw/before6.rules)" > /etc/ufw/before6.rules
fi

## create profiles for each wi-fi interface
INTERFACES=($(iwconfig 2>/dev/null | grep 'IEEE' | awk '{print $1}'))

if [ ${#INTERFACES[@]} -eq 0 ]; then
    echo "[WARN] No wireless network interface found. Skipping Wi-Fi configuration."
else
    for iface in "${INTERFACES[@]}"; do
		# wi-fi as client
		cat <<EOF | tee "$NORM_PROFILE/20-$iface-managed.network" "$AP_PROFILE/20-$iface-managed.network" > /dev/null
[Match]
Name=$iface

[Network]
DHCP=yes
WPAConfigFile=/etc/wpa_supplicant/wpa_supplicant-$iface.conf

[DHCPv4]
RouteMetric=$((200 + jj))

[IPv6AcceptRA]
RouteMetric=$((200 + jj))

[Address]
MPTCPSubflow=no

[Link]
WiFiPowerSave=disable
EOF

		WPA_CONF="/etc/wpa_supplicant/wpa_supplicant-$iface.conf"
##            if [ ! -f "$WPA_CONF" ]; then
##                # These lines requires more testing
##                echo "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev" > "$WPA_CONF"
##                echo "update_config=1" >> "$WPA_CONF"
##            fi
		# Grab wifi networks and pass from network-manager, if anything still there
		if [ -d /etc/NetworkManager/system-connections/ ]; then
			for knownwlans in /etc/NetworkManager/system-connections/*; do
			if grep -q 'type=wifi' "$knownwlans"; then
				SSID=$(grep -oP 'ssid=\K.*' "$knownwlans")
				PSK=$(grep -oP 'psk=\K.*' "$knownwlans")

				if [ -n "$SSID" ] && [ -n "$PSK" ] && ! grep -q -F "ssid=\"$SSID\"" "$WPA_CONF"; then
					echo "[INFO] Adding new network '$SSID' to $WPA_CONF"
					cat <<EONET >> "$WPA_CONF"
network={
    ssid="$SSID"
    psk="$PSK"
}
EONET
				fi
			fi
			done
		fi
		systemctl enable "wpa_supplicant@$iface.service"

		# the first wifi interface can be enabled as access point
        if [[ "$iface" == "${INTERFACES[0]}" ]]; then
            ufw allow in on "$iface" to any port 546 proto udp # DHCPv6 Client
            ufw allow in on "$iface" to any port 547 proto udp # DHCPv6 Server
            ufw allow in on "$iface" from any port 68 to any port 67 proto udp # DHCPv4
            ufw allow in on "$iface" to any port 53 # DNS

            # AP Profile (with IPv6 support)
			rm $AP_PROFILE/20-$iface-managed.network
            cat <<EOF > "$AP_PROFILE/40-$iface-ap.network"
[Match]
Name=$iface
WLANMode=ap

[Network]
Address=192.168.168.1/24
Address=fd42:42:42::1/64
DHCPServer=yes
IPv6SendRA=yes
IPMasquerade=yes

[Address]
MPTCPSubflow=no

[DHCPServer]
DNS=8.8.8.8 1.1.1.1
DNS=2001:4860:4860::8888 2606:4700:4700::1111

[IPv6SendRA]
DNS=2001:4860:4860::8888 2606:4700:4700::1111

[Link]
WiFiPowerSave=disable
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
        fi
    done
fi

# Hostapd service configuration
cat <<'EOF' > /etc/systemd/system/hostapd.service
[Unit]
Description=Access point and authentication server for Wi-Fi and Ethernet
After=network.target
ConditionFileNotEmpty=/etc/hostapd/hostapd.conf

[Service]
Type=exec
Restart=on-failure
RestartSec=2
Environment=DAEMON_CONF=/etc/hostapd/hostapd.conf
EnvironmentFile=-/etc/default/hostapd
ExecStart=/usr/sbin/hostapd -P /run/hostapd.pid $DAEMON_OPTS ${DAEMON_CONF}

[Install]
WantedBy=multi-user.target
EOF

## for each ethernet/usb/tether interface create profiles
jj=0
for iface in $(ls /sys/class/net); do
    if [ "$iface" == "lo" ] || [[ "$iface" == *bond* ]] || [ -d "/sys/class/net/$iface/wireless" ]; then
        continue
    fi
    cat <<EOF | tee "$NORM_PROFILE/10-$iface.network" "$AP_PROFILE/10-$iface.network" > /dev/null
[Match]
Name=$iface

[Link]
EnergyEfficientEthernet=false
RequiredForOnline=routable

[Network]
DHCP=yes

[DHCPv4]
RouteMetric=$((100 + jj))

[IPv6AcceptRA]
RouteMetric=$((100 + jj))
EOF

    cat <<EOF > "$DISPATCHER_DIR/30-$iface-mptcp-subflow.sh"
#!/bin/sh
if [ "\$IFACE" = "$iface" ]; then
    IP_ADDR=\$(ip -4 addr show dev "\$IFACE" | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}')
    if [ -n "\$IP_ADDR" ]; then
        /sbin/ip mptcp endpoint add "\$IP_ADDR" dev "\$IFACE" subflow
    fi
fi
EOF

    chmod +x "$DISPATCHER_DIR/30-$iface-mptcp-subflow.sh"
    ((jj++))
done

## Enable the new settings
systemctl daemon-reload
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable networkd-dispatcher

## Setting and enabling mptcp service
sed -i \
-e 's/^#* *path-manager=.*/path-manager=default/' \
-e 's/^#* *load-plugins=.*/load-plugins=addr_adv/' \
-e 's/^#* *addr-flags=.*/addr-flags=subflow,signal,fullmesh/' \
/etc/mptcpd/mptcpd.conf

systemctl enable mptcp

systemctl disable systemd-networkd-wait-online.service 2>/dev/null
systemctl mask systemd-networkd-wait-online.service

ufw reload
ufw --force enable
echo "Now You should restart to give a try - ...keep monitor and keyboard on Your arm lenght range :D"

exit 0
