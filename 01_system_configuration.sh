#!/bin/bash

## This script prepare the OS to run VLXframeflow suite

if [ "$EUID" -ne 0 ]; then
  echo "[ERR]: This script requires root privileges."
  exit 1
fi

VLXsuite_DIR="/opt/VLXframeflow"
VLXlogs_DIR="/opt/VLXflowlogs"
CRON_script="$VLXsuite_DIR/04_maintenance.sh"
CRON_JOB="@reboot $CRON_script start 2>&1"
GITHUB_URL="https://github.com/viruslox/VLXframeflow.git"

systemctl enable --now ssh
systemctl unmask hostapd 
getty_file=($(find /etc/systemd/system/ -name 'getty*service'))
getty_conf_line="ExecStart=-/sbin/agetty --noreset --noclear --issue-file=/etc/issue:/etc/issue.d:/run/issue.d:/usr/lib/issue.d - \${TERM}"
sed -i "s#^ExecStart=-/sbin/agetty.*#${getty_conf_line}#" "${getty_file[@]}"
getty_block="ImportCredential=tty.virtual.%I.agetty.*:agetty.
ImportCredential=tty.virtual.%I.login.*:login.
ImportCredential=agetty.*
ImportCredential=login.*
ImportCredential=shell.*"
for file in "${getty_file[@]}"; do
    awk -v block="$getty_block" '
    {
        if (found_sighup) {
            if ($0 ~ /^$/) {
                print block
            }
            found_sighup = 0
        }
        if ($0 ~ /SendSIGHUP=yes/) {
            found_sighup = 1
        }
        print $0
    }
    ' "$file" > "$file.tmp"
    if [ $? -eq 0 ]; then
        mv "$file.tmp" "$file"
    else
        echo "[ERR] Error editing $file."
        rm "$file.tmp"
    fi
done


read -r -p "Do you want to perform a full system update and reconfigure APT sources? (Y/n) " response
if [[ -z "$response" || "$response" =~ ^[yY]$ ]]; then
    apt -y purge qt* *gtk* adwaita*
    apt -y autoremove
    apt -y upgrade
    apt -y dist-upgrade
    apt -y autoremove
    wget https://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2024.9.1_all.deb
    dpkg -i `pwd`/deb-multimedia-keyring_2024.9.1_all.deb

    apt -y update
    apt -y install aptitude apt dpkg
    apt -y modernize-sources
    apt -y autoremove
    apt -y upgrade
    apt -y dist-upgrade

    aptitude -y purge '~o'
    aptitude -y purge '~c'

    APTGET_FILE="/etc/apt/sources.list.d/debian.sources"
	DEBMLTMEDIA_FILE="/etc/apt/sources.list.d/unofficial-multimedia-packages.sources"
 
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


	cat <<EOF > $DEBMLTMEDIA_FILE
# Modernized from /etc/apt/sources.list
Types: deb
URIs: https://www.deb-multimedia.org/
Suites: testing
Components: main non-free
Signed-By: /usr/share/keyrings/deb-multimedia-keyring.pgp
EOF

else
    echo "[INFO]: Skipping system update and APT reconfiguration as requested."
fi


apt --fix-broken install
apt-get -y update
if [[ -f /home/pkg.list ]]; then
    read -r -p "Found a list of previously installed packages. Do you want to try to re-install them? (y/N) " response
    if [[ "$response" =~ ^[yY]$ ]]; then
        xargs -a /home/pkg.list apt-get -y install
    fi
fi
apt-get -y install ffmpeg libavdevice-dev libcamera-dev libcamera-tools libcamera-v4l2 dov4l dv4l qv4l2 v4l-conf v4l-utils uvccapture libuvc-dev uvcdynctrl gpsd gpsd-clients jq git hostapd systemd-resolved wireless-tools ufw postfix

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
mkdir -p $VLXsuite_DIR $VLXlogs_DIR
chown -Rf $answnewuser:$answnewuser $VLXsuite_DIR $VLXlogs_DIR

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
if ! crontab -l 2>/dev/null | grep -qF "$CRON_GPS start"; then
    # Use a subshell to safely add the new job to the existing crontab
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    if [ $? -eq 0 ]; then
        echo "Cron job updated"
        echo "New crontab entries:"
        crontab -l | grep --color=auto "$CRON_GPS start"
    else
        echo "[ERR] Failed to add the cron job." >&2
        exit 1
    fi
fi

echo "[OK]: System configuration complete."
echo "Starting by now You are supposed to use $answnewuser" 

exit 0
