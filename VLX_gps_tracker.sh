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

if [ -f ~/.frameflow_profile ]; then
    source ~/.frameflow_profile
else
    echo "[ERR] ~/.frameflow_profile not found."
    exit 1
fi

if [ -z "$VLXsuite_DIR" ]; then
	VLXsuite_DIR="/opt/VLXframeflow"
fi
if [ -z "$VLXlogs_DIR" ]; then
	$VLXlogs_DIR="/opt/VLXflowlogs"
fi

if [ -z "$GPSPORT" ]; then
	GPSPORT=1198
fi

if [ -z "$RTSP_URL" ]; then
    echo "[ERR] RTSP_URL is not set in ~/.frameflow_profile"
    exit 1
fi

GPSD_PID="$VLXlogs_DIR/gps_gpsd.pid"
GPSD_LOG="$VLXlogs_DIR/gps_gpsd.log"
SEND_PID="$VLXlogs_DIR/gps_api.pid"
SEND_LOG="$VLXlogs_DIR/gps_api.log"

device=/dev/$(dmesg | grep -E 'tty(ACM|USB)[0-9]+' | grep -v 'disconnect' | tail -n 1 | grep -o 'tty[A-Z]*[0-9]*')
GPSD_BIN=/usr/sbin/gpsd

status_gpsd() {
    pgrep -f "$GPSD_BIN -P $GPSD_PID" | while read -r p; do
        if [ ! -f "$GPSD_PID" ] || [ "$p" != "$(cat "$GPSD_PID")" ]; then
            echo "[WARN] Found orphan gpsd process with PID $p. Killing it."
            kill "$p" 2>/dev/null
        fi
    done

    if [ -f "$GPSD_PID" ]; then
        PID=$(cat "$GPSD_PID")
        if ps -p "$PID" > /dev/null; then
            echo "GPSD already running with PID: $PID"
            echo "Check logs: tail -f $GPSD_LOG"
        else
            echo "[WARN] GPSD PID file found but process does not exist, removing PID file"
            rm "$GPSD_PID"
        fi
    else
        echo "[INFO] GPSD PID file not found"
    fi
}

status_sender() {
    pgrep -f "gpspipe -w localhost:$GPSPORT" | while read -r p; do
        if [ ! -f "$SEND_PID" ] || [ "$p" != "$(cat "$SEND_PID")" ]; then
            echo "[WARN] Found orphan gpspipe process with PID $p. Killing it."
            kill "$p" 2>/dev/null
        fi
    done

    if [ -f "$SEND_PID" ]; then
        PID=$(cat "$SEND_PID")
        if ps -p "$PID" > /dev/null; then
            echo "gpspipe already running with PID: $PID"
            echo "Check logs: tail -f $SEND_LOG"
        else
            echo "[WARN] gpspipe PID file found but process does not exist, removing PID file"
            rm "$SEND_PID"
        fi
    else
        echo "[INFO] gpspipe PID file not found"
    fi
}

stop_gpsd() {
    if [ -f "$GPSD_PID" ]; then
        echo "Killing gpsd..."
        kill "$(cat "$GPSD_PID")" 2>/dev/null
        rm "$GPSD_PID" 2>/dev/null
        echo "Done."
    else
        echo "[INFO] GPSD PID file not found."
    fi
    sleep 5
    status_gpsd
}

stop_sender() {
    if [ -f "$SEND_PID" ]; then
        echo "Killing gpspipe..."
        kill "$(cat "$SEND_PID")" 2>/dev/null
        rm "$SEND_PID" 2>/dev/null
        echo "Done."
    else
        echo "[INFO] gpspipe PID file not found."
    fi
    sleep 5
    status_sender
}

start_gpsd() {
    if [ -z "$device" ]; then
        echo "[ERR] No GPS device found. Exiting."
        exit 1
    fi

    echo "Launching gpsd in background..."
    GPSD_CMD="$GPSD_BIN -P $GPSD_PID -D5 -N -n -S $GPSPORT $device"
    $GPSD_CMD >/dev/null 2>"$GPSD_LOG" &
    echo $! > "$GPSD_PID"
    echo "gpsd launched. PID saved to $GPSD_PID."

    echo "[INFO] Waiting for gpsd to be ready on port $GPSPORT..."
    local attempts=0
    while ! ss -lnt | grep -q ":$GPSPORT"; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 10 ]; then
            echo "[ERR]: gpsd failed to start and listen on port $GPSPORT after 10 seconds."
            echo "--- Last 20 lines of gpsd log ---"
            tail -n 20 "$GPSD_LOG"
            return 1 # Indicate failure
        fi
        sleep 1
    done
    
    echo "[OK]: gpsd is ready."
    return 0 # Indicate success
}

start_sender() {
    echo "Launching gpspipe sender in background..."

    (
        gpspipe -w "localhost:$GPSPORT" | grep --line-buffered '"class":"TPV"' | \
        while read -r line; do
            JSON_PAYLOAD=$(echo "$line" | jq -c '{ "lat": .lat, "lon": .lon, "alt": .altMSL, "pos_error": (.epx // 0) }')

            if [[ -n "$JSON_PAYLOAD" && "$JSON_PAYLOAD" != "null" ]]; then
                curl -s -X POST "$API_URL" \
                     -H "Content-Type: application/json" \
                     -H "Authorization: Bearer $AUTH_TOKEN" \
                     -d "$JSON_PAYLOAD"
            fi
        done
    ) >"$SEND_LOG" 2>&1 &
    echo $! > "$SEND_PID"
    echo "gpspipe sender launched. PID saved to $SEND_PID."
}

case "$1" in
    start)
        stop_sender
		stop_gpsd
        start_gpsd || { echo "[FATAL] Could not start gpsd daemon. Aborting."; exit 1; }
        start_sender
        ;;
    stop)
        stop_sender
		stop_gpsd
        ;;
    status)
        status_gpsd
		status_sender
        ;;
    *)
		status_gpsd
		status_sender
		echo "Usage: $0 {start|stop|status}"
        ;;
esac

exit 0
