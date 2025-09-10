#!/bin/bash

dedicated_user=$(ls -ld /opt/VLXframeflow | awk '{print $3}')
if [ "$(id -u)" -eq 0 ]; then
  echo "[ERR] Please launch this script with the dedicated user."
  echo "Never, never use root when not necessaire."
  exit 1
elif [ "$USER" != "$dedicated_user" ]; then
	echo "Only $dedicated_user can correctly execute this script."
fi

if [ -f ~/.frameflow_profile ]; then
    source ~/.frameflow_profile
else
    echo "[ERR] ~/.frameflow_profile not found."
    exit 1
fi

if [ -z "$API_URL" ]; then
    echo "[ERR] API_URL is not set in ~/.frameflow_profile"
    exit 1
fi

# Loop indefinitely to send updates
while true; do
    # Get the latest speed value from gpspipe
    # We use 'tail -n 1' to ensure we only get the very last line
    SPEED=$(gpspipe -w 127.0.0.1:1198 | grep -o '"speed":[0-9]*\.[0-9]*' | tail -n 1 | cut -d ':' -f 2)

    # Check if a valid speed value was captured
    if [ -n "$SPEED" ]; then
        # Send a JSON POST request to the API
        curl -X POST "$API_URL" -H "Content-Type: application/json" -d "{\"speed\":${SPEED}}"
    fi

    # Wait a few seconds before sending the next update
    sleep 2
done