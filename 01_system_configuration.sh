#!/bin/bash

## This script prepare the OS to run VLXframeflow suite

if [ "$EUID" -ne 0 ]; then
  echo "[ERR]: This script requires root privileges."
  exit 1
fi

VLXsuite_DIR="/opt/VLXframeflow"
VLXlogs_DIR="/opt/VLXflowlogs"
MEDIAMTX_DIR="/opt/mediamtx"
CRON_script="$VLXsuite_DIR/04_maintenance.sh"
CRON_JOB="@reboot $CRON_script start 2>&1"
GITHUB_URL="https://github.com/viruslox/VLXframeflow.git"

systemctl enable --now ssh
systemctl unmask hostapd 

mkdir -p /etc/systemd/system/getty@.service.d/
getty_file="/etc/systemd/system/getty@.service.d/override.conf"
GETTY_OVERRIDE_CONF="[Service]
ExecStart=
ExecStart=-/sbin/agetty --noreset --noclear --issue-file=/etc/issue:/etc/issue.d:/run/issue.d:/usr/lib/issue.d - %I \${TERM}
ImportCredential=tty.virtual.%I.agetty.*:agetty.
ImportCredential=tty.virtual.%I.login.*:login.
ImportCredential=agetty.*
ImportCredential=login.*
ImportCredential=shell.*"

echo "$GETTY_OVERRIDE_CONF" > "$getty_file"
echo "[INFO]: Applying systemd override for getty.service..."
systemctl daemon-reload

echo "We're about to reconfigure the whole OS including uninstall Desktop apps and graphical GUI - You can skip this step"
read -r -p "Do you want to perform a full system update and reconfigure APT sources? (Y/n) " response
if [[ -z "$response" || "$response" =~ ^[yY]$ ]]; then

	# Removing desktop / GUI packages
	tasksel remove desktop gnome-desktop xfce-desktop kde-desktop cinnamon-desktop mate-desktop lxde-desktop lxqt-desktop
    apt -y purge qt* *gtk* adwaita*
	apt -y purge cloud-guest-utils cloud-init
    apt -y autoremove

	# Upgrading the OS base
    apt -y upgrade
    apt -y dist-upgrade
    apt -y autoremove

	# Finding the latest deb-multimedia-keyring version..."
	KEYRING_PAGE_URL="https://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/"
	LATEST_KEYRING_FILE=$(curl -s "$KEYRING_PAGE_URL" | grep -o 'deb-multimedia-keyring_[0-9.]*_all\.deb' | sort -V | tail -n 1)
	if [ -z "$LATEST_KEYRING_FILE" ]; then
	    echo "[ERR]: Could not find the latest deb-multimedia-keyring file."
	else
		LATEST_KEYRING_URL="${KEYRING_PAGE_URL}${LATEST_KEYRING_FILE}"
		wget -q "$LATEST_KEYRING_URL" -O "/tmp/$LATEST_KEYRING_FILE"
		if [ $? -ne 0 ]; then
	    	echo "[ERR]: Failed to download the keyring package."
		else
		dpkg -i "/tmp/$LATEST_KEYRING_FILE"
		rm "/tmp/$LATEST_KEYRING_FILE" # Pulisce il file scaricato
		fi
	fi

	# Download Armbian keyring
	wget -qO- https://beta.armbian.com/armbian.key | gpg --dearmor | tee /usr/share/keyrings/armbian.gpg > /dev/null

	# Redundant, but hopefully it fixes most of the possible errors from previous steps
    apt -y update
    apt -y install aptitude apt dpkg
    apt -y modernize-sources
    apt -y autoremove
    apt -y upgrade
    apt -y dist-upgrade

    aptitude -y purge '~o'
    aptitude -y purge '~c'

	# Reconfiguring APT
	APTGET_FILE="/etc/apt/sources.list.d/debian.sources"
	DEBMLTMEDIA_FILE="/etc/apt/sources.list.d/unofficial-multimedia-packages.sources"
	ARMBIAN_FILE="/etc/apt/sources.list.d/armbian-beta.sources"

    cat <<EOF > $APTGET_FILE
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


	cat <<EOF > $DEBMLTMEDIA_FILE
Types: deb
URIs: https://www.deb-multimedia.org/
Suites: testing
Components: main non-free
Signed-By: /usr/share/keyrings/deb-multimedia-keyring.pgp
EOF

	cat <<EOF > $ARMBIAN_FILE
Types: deb
URIs: https://beta.armbian.com/
Suites: sid
Components: main sid-utils sid-desktop
Signed-By: /usr/share/keyrings/armbian.gpg
EOF

else
    echo "[INFO]: Skipping system update and APT reconfiguration as requested."
fi

# Let's setup all what we need
apt --fix-broken install
apt-get -y update
if [[ -f /home/pkg.list ]]; then
    read -r -p "Found a list of previously installed packages. Do you want to try to re-install them? (y/N) " response
    if [[ "$response" =~ ^[yY]$ ]]; then
        xargs -a /home/pkg.list apt-get -y install
    fi
fi
apt-get -y install firmware-linux firmware-linux-free firmware-linux-nonfree firmware-misc-nonfree
apt-get -y install hostapd systemd-resolved wireless-tools ufw postfix firmware-atheros firmware-brcm80211 firmware-iwlwifi
apt-get -y install ffmpeg libavdevice-dev libcamera-dev libcamera-tools libcamera-v4l2 dov4l dv4l qv4l2 v4l-conf v4l-utils
apt-get -y install uvccapture libuvc-dev gpsd gpsd-clients jq git screen tasksel

## Reorder passwd file and get unprileged users list
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
elif [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -ge "${#userlist[@]}" ]; then
    echo "[ERR]: Invalid selection. Exit."
    exit 1
else
    answnewuser=${userlist[$CHOICE]}
fi
usermod -a -G crontab,dialout,tty,video,audio,plugdev,netdev,i2c,bluetooth $answnewuser
loginctl enable-linger $answnewuser
mkdir -p $VLXsuite_DIR $VLXlogs_DIR $MEDIAMTX_DIR
chown -Rf $answnewuser:$answnewuser $VLXsuite_DIR $VLXlogs_DIR $MEDIAMTX_DIR

echo "sysctl kernel.dmesg_restrict=0" > /etc/sysctl.d/99-disable-dmesg-restrict.conf
sysctl --system


# GitHub VLXframeflow Download
echo "[INFO]: Attempting to clone project from $GITHUB_URL..."
if (cd $VLXsuite_DIR && sudo -u "$answnewuser" git clone "$GITHUB_URL" .); then
    echo "[OK]: GitHub project cloned successfully."
else
    echo "[ERR]: Failed to clone the repository. Please check the URL and network connection."
fi

# Check if the cron job already exists to avoid duplicates
if ! crontab -l 2>/dev/null | grep -qF "$CRON_script"; then
    # Use a subshell to safely add the new job to the existing crontab
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    if [ $? -eq 0 ]; then
        echo "Cron job updated"
        echo "New crontab entries:"
        crontab -l | grep --color=auto "$CRON_script start"
    else
        echo "[ERR] Failed to add the cron job." >&2
        exit 1
    fi
fi

## Allow dmesg for nornal users
echo kernel.dmesg_restrict = 0 | tee -a /etc/sysctl.d/10-local.conf >/dev/null
sysctl kernel.dmesg_restrict=0

echo "[OK]: System configuration complete."
echo "Starting by now You are supposed to use $answnewuser" 

exit 0
