#!/bin/bash

# Suite setup, update and utils

GITHUB_URL="https://github.com/viruslox/VLXframeflow.git"
# IF You wish to change PATH, be sure that You have write rights there."
VLXsuite_DIR="/opt/VLXframeflow"
VLXlogs_DIR="/opt/VLXflowlogs"

dedicated_user=$(ls -ld /opt/VLXframeflow | awk '{print $3}')
if [ "$(id -u)" -eq 0 ]; then
  echo "[ERR] Please launch this script with the dedicated user."
  echo "Never, never use root when not necessaire."
  exit 1
elif [ "$USER" != "$dedicated_user" ]; then
	echo "Only $dedicated_user can correctly execute this script."
	exit 1
fi

if [ ! -f ~/.frameflow_profile ]; then
    touch ~/.frameflow_profile
	echo "# if zero means not enabled; 1 means enable only the first device found, 2 only the first 2 devices found..." > ~/.frameflow_profile
	echo "ENABLED_DEVICES=0" >> ~/.frameflow_profile
	echo "RTSP_URL=\"rtsps://<host>:<port>/<path>/<key>\"" >> ~/.frameflow_profile
	echo "# This usually works with USB - HDMI-IN adapters" >> ~/.frameflow_profile
	echo "AUDIODEV='card.*USB'" >> ~/.frameflow_profile
	echo "# Define the API endpoint URL" >> ~/.frameflow_profile
	echo "#API_URL=\"http://your-server-ip:3000/update-gps\"" >> ~/.frameflow_profile
 	echo "# IF You wish to change PATH, be sure that You have write rights there." >> ~/.frameflow_profile
	echo "VLXsuite_DIR=\"${VLXsuite_DIR}\"" >> ~/.frameflow_profile
	echo "VLXlogs_DIR=\"${VLXlogs_DIR}\"" >> ~/.frameflow_profile
fi

mkdir -p ~/.config/systemd/user/
cd $VLXsuite_DIR/
git reset --hard
git pull -f --no-commit --no-verify https://github.com/viruslox/VLXframeflow.git

chmod 700 /opt/VLXframeflow/*.sh

echo "[OK]: Done!"

exit 0
