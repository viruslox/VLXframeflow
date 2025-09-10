#!/bin/bash

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
fi

mkdir -p ~/.config/systemd/user/
cd /opt/VLXframeflow
#wget ...ehhh ancora non ci sono :(
#wget

##touch ~/.config/systemd/user/gps_tracker.service
##cat <<EOF > ~/.config/systemd/user/gps_tracker.service
## ...
##EOF

systemctl --user daemon-reload
#systemctl --user enable gps_tracker.service

chmod 700 /opt/VLXframeflow/*.sh

echo "[OK]: Done!"

exit 0