#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "[ERR]: This script requires root privileges. Please run it as root or use sudo."
  exit 1
fi

apt -y modernize-sources

APTGET_FILE="/etc/apt/sources.list.d/debian.sources"
cat <<EOF > $APTGET_FILE
# Modernized from /etc/apt/sources.list
Types: deb
URIs: https://deb.debian.org/debian/
Suites: testing
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# Modernized from /etc/apt/sources.list
Types: deb
URIs: http://security.debian.org/debian-security/
Suites: testing-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# Modernized from /etc/apt/sources.list
Types: deb
URIs: https://deb.debian.org/debian/
Suites: testing-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# Modernized from /etc/apt/sources.list
Types: deb
URIs: https://deb.debian.org/debian/
Suites: experimental
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

DEBMLTMEDIA_FILE="/etc/apt/sources.list.d/unofficial-multimedia-packages.sources"
cat <<EOF > $DEBMLTMEDIA_FILE
# Modernized from /etc/apt/sources.list
Types: deb
URIs: https://www.deb-multimedia.org/
Suites: testing
Components: main non-free
Signed-By: /etc/apt/trusted.gpg.d/deb-multimedia-keyring.asc
EOF

apt-get -y update
apt-get -y install ffmpeg libcamera-dev libcamera-tools libcamera-v4l2 dov4l dv4l qv4l2 v4l-conf v4l-utils uvccapture libuvc-dev uvcdynctrl gpsd gpsd-clients

pwck -s

userlist=($(awk -F: '($3>=1000)&&($1!="nobody")&&($NF!="/usr/sbin/nologin")&&($NF!="/bin/false"){print $1}' /etc/passwd))

for i in "${!userlist[@]}"; do
    echo "[$i] ${userlist[$i]}"
done
echo "[N] Create new dedicated user"
echo "[X] Cancel operation and Quit"
echo ""
read -p "Enter your choice and press <Enter>: " CHOICE

# Handle quitting
if [[ "$CHOICE" =~ ^[xX]$ ]]; then
    echo "[INFO]: Operation cancelled by user. Exit."
    exit 0
fi

# Handle invalid (non-numeric or out-of-bounds) input
if [[ "$CHOICE" =~ ^[nN]$ ]]; then
	read -p "Create new dedicated username [default: frameflow]: " answnewuser
	answnewuser=${answnewuser:-frameflow}
	adduser --home /home/$answnewuser --shell /bin/bash --gecos "VLXframeflow tech user" $answnewuser
elif [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -ge "${#userlist[@]}" ]; then
    echo "[ERR]: Invalid selection. Exit."
    exit 1
else
	answnewuser=${userlist[$CHOICE]}
fi
usermod -a -G crontab,dialout,tty,video,audio,plugdev,netdev,i2c,bluetooth,pipewire $answnewuser
loginctl enable-linger $answnewuser
mkdir -p /opt/VLXframeflow
chown -Rf $answnewuser:$answnewuser /opt/VLXframeflow

echo "sysctl kernel.dmesg_restrict=0" > /etc/sysctl.d/99-disable-dmesg-restrict.conf
sysctl --system

echo "[OK]: System configuration complete."
echo "Starting by now You are supposed to use $answnewuser" 

exit 0