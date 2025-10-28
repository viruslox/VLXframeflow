#!/bin/bash

# Suite setup, update and utils

GITHUB_URL="https://github.com/viruslox/VLXframeflow.git"
# IF You wish to change PATH, be sure that You have write rights there."
VLXsuite_DIR="/opt/VLXframeflow"
VLXlogs_DIR="/opt/VLXflowlogs"
PROFILE_FILE="$HOME/.frameflow_profile"

dedicated_user=$(ls -ld /opt/VLXframeflow | awk '{print $3}')
if [ "$(id -u)" -eq 0 ]; then
  echo "[ERR] Please launch this script with the dedicated user."
  echo "Never, never use root when not necessaire."
  exit 1
elif [ "$USER" != "$dedicated_user" ]; then
	echo "Only $dedicated_user can correctly execute this script."
	exit 1
fi

touch "$PROFILE_FILE"

# Check for VLXsuite_DIR
if ! grep -q "VLXsuite_DIR=" "$PROFILE_FILE"; then
    echo "[INFO] Adding 'VLXsuite_DIR' to profile."
    echo -e "# IF You wish to change PATH, be sure that You have write rights there." >> "$PROFILE_FILE"
    echo "VLXsuite_DIR=\"${VLXsuite_DIR}\"" >> "$PROFILE_FILE"
fi

# Check for VLXlogs_DIR
if ! grep -q "VLXlogs_DIR=" "$PROFILE_FILE"; then
    echo "[INFO] Adding 'VLXlogs_DIR' to profile."
    echo -e "VLXlogs_DIR=\"${VLXlogs_DIR}\"" >> "$PROFILE_FILE"
fi

if ! grep -q "ENABLED_DEVICES=" "$PROFILE_FILE"; then
    echo "[INFO] Adding 'ENABLED_DEVICES' to profile."
    echo -e "\n# if zero means not enabled; 1 means enable only the first device found, 2 only the first 2 devices found..." >> "$PROFILE_FILE"
    echo "ENABLED_DEVICES=0" >> "$PROFILE_FILE"
fi

if ! grep -q "RTSP_URL=" "$PROFILE_FILE"; then
    echo "[INFO] Adding 'RTSP_URL' to profile."
    echo -e "RTSP_URL=\"#rtsps://<host>:<port>/<path>/<key>\"" >> "$PROFILE_FILE"
fi

if ! grep -q "RTSP_URL=" "$PROFILE_FILE"; then
    echo "[INFO] Adding 'SRT_URL' to profile."
    echo -e "SRT_URL=\"#srt://<host>:<port>?streamid=publish:<path>/<key>\"" >> "$PROFILE_FILE"
fi

# Check for AUDIODEV
if ! grep -q "AUDIODEV=" "$PROFILE_FILE"; then
    echo "[INFO] Adding 'AUDIODEV' to profile."
    echo -e "\n# This is used to select the "microfone" which pickup the audio, usually it works with USB - HDMI-IN adapters" >> "$PROFILE_FILE"
    echo "AUDIODEV='card.*USB'" >> "$PROFILE_FILE"
fi

if ! grep -q "API_URL=" "$PROFILE_FILE"; then
    echo "[INFO] Adding placeholder for 'API_URL' to profile."
    echo -e "\n# Define the "GPS overlay" API endpoint URL" >> "$PROFILE_FILE"
    echo "#API_URL=\"http://your-server-ip:3000/update-gps\"" >> "$PROFILE_FILE"
fi

if ! grep -q "AUTH_TOKEN=" "$PROFILE_FILE"; then
    echo "[INFO] Adding placeholder for "GPS overlay" 'AUTH_TOKEN' to profile."
    echo -e "#AUTH_TOKEN=\"<your api token>\"" >> "$PROFILE_FILE"
fi

mkdir -p ~/.config/systemd/user/
cd $VLXsuite_DIR/
git reset --hard
git pull -f --no-commit --no-verify https://github.com/viruslox/VLXframeflow.git

chmod 700 /opt/VLXframeflow/*.sh

echo "[OK]: Done!"

exit 0
