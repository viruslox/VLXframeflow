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

if [ -z "$GPSPORT" ]; then
	GPSPORT=1198
fi

if [ -z "$RTSP_URL" ]; then
    echo "[ERR] RTSP_URL is not set in ~/.frameflow_profile"
    exit 1
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PID_FILE="$SCRIPT_DIR/gps_tracker.pid"
LOG_FILE="$SCRIPT_DIR/gps_tracker.log"
SPEED_PID="$SCRIPT_DIR/gps_speed.pid"
SPEED_LOG="$SCRIPT_DIR/gps_speed.log"
SPEED_FILE="$SCRIPT_DIR/gps_speed"
SPEED_READER_PID="$SCRIPT_DIR/gps_reader.pid"

device=/dev/$(dmesg | grep -E 'tty(ACM|USB)[0-9]+' | grep -v 'disconnect' | tail -n 1 | grep -o 'tty[A-Z]*[0-9]*')
GPSD=/usr/sbin/gpsd
FFMPEG_CMD=$(which ffmpeg)

status_gpsd() {
    pgrep -f "$GPSD -P $PID_FILE" | while read -r p; do
        if [ ! -f "$PID_FILE" ] || [ "$p" != "$(cat "$PID_FILE")" ]; then
            echo "[WARN] Found orphan gpsd process with PID $p. Killing it."
            kill "$p" 2>/dev/null
        fi
    done

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null; then
            echo "GPSD already running with PID: $PID"
            echo "Check logs: tail -f $LOG_FILE"
        else
            echo "[WARN] GPSD PID file found but process does not exist, removing PID file"
            rm "$PID_FILE"
        fi
    else
        echo "[INFO] GPSD PID file not found"
    fi
}

status_speedreader() {
    pgrep -f "gpspipe -w 127.0.0.1:$GPSPORT" | while read -r p; do
        if [ ! -f "$SPEED_READER_PID" ] || [ "$p" != "$(cat "$SPEED_READER_PID")" ]; then
            echo "[WARN] Found orphan speed reader process with PID $p. Killing it."
            kill "$p" 2>/dev/null
        fi
    done

    if [ -f "$SPEED_READER_PID" ]; then
        PID=$(cat "$SPEED_READER_PID")
        if ps -p "$PID" > /dev/null; then
            echo "Speed reader already running with PID: $PID"
        else
            echo "[WARN] Speed reader PID file found but process does not exist, removing PID file"
            rm "$SPEED_READER_PID"
        fi
    else
        echo "[INFO] Speed reader PID file not found."
    fi
}

status_speedsender() {
    pgrep -f "ffmpeg -y -f lavfi" | while read -r p; do
        if [ ! -f "$SPEED_PID" ] || [ "$p" != "$(cat "$SPEED_PID")" ]; then
            echo "[WARN] Found orphan FFmpeg process with PID $p. Killing it."
            kill "$p" 2>/dev/null
        fi
    done

    if [ -f "$SPEED_PID" ]; then
        PID=$(cat "$SPEED_PID")
        if ps -p "$PID" > /dev/null; then
            echo "FFmpeg already running with PID: $PID"
            echo "Check logs: tail -f $SPEED_LOG"
        else
            echo "[WARN] FFmpeg PID file found but process does not exist, removing PID file"
            rm "$SPEED_PID"
        fi
    else
        echo "[INFO] FFmpeg PID file not found"
    fi
}

stop_gpsd() {
    if [ -f "$PID_FILE" ]; then
        echo "Killing gpsd..."
        kill "$(cat "$PID_FILE")" 2>/dev/null
        rm "$PID_FILE" 2>/dev/null
        echo "Done."
    else
        echo "[INFO] GPSD PID file not found."
    fi
    sleep 5
    status_gpsd
}

stop_speedreader() {
    if [ -f "$SPEED_READER_PID" ]; then
        echo "Killing speed reader process..."
        kill "$(cat "$SPEED_READER_PID")" 2>/dev/null
        rm "$SPEED_READER_PID" 2>/dev/null
    else
        echo "[INFO] Speed reader PID file not found."
    fi
    sleep 5
    status_speedreader
}

stop_speedsender() {
    if [ -f "$SPEED_PID" ]; then
        echo "Killing FFmpeg..."
        kill "$(cat "$SPEED_PID")" 2>/dev/null
        rm "$SPEED_PID" 2>/dev/null
        echo "Done."
    else
        echo "[INFO] FFmpeg PID file not found."
    fi
    sleep 5
    status_speedsender
}

start_gpsd() {
    if [ -z "$device" ]; then
        echo "[ERR] No GPS device found. Exiting."
        exit 1
    fi

    echo "Launching gpsd in background..."
    GPSD_CMD="$GPSD -P $PID_FILE -D5 -N -n -S $GPSPORT $device"
    $GPSD_CMD >/dev/null 2>"$LOG_FILE" &
    echo $! > "$PID_FILE"
    echo "gpsd launched. PID saved to $PID_FILE."

    echo "[INFO] Waiting for gpsd to be ready on port $GPSPORT..."
    local attempts=0
    while ! ss -lnt | grep -q ":$GPSPORT"; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 10 ]; then
            echo "[ERR]: gpsd failed to start and listen on port $GPSPORT after 10 seconds."
            echo "--- Last 20 lines of gpsd log ---"
            tail -n 20 "$LOG_FILE"
            return 1 # Indicate failure
        fi
        sleep 1
    done
    
    echo "[OK]: gpsd is ready."
    return 0 # Indicate success
}

start_speedreader() {
    echo "Launching speed reader..."
    (gpspipe -w localhost:$GPSPORT | while read -r line; do
        if echo "$line" | grep -q '"class":"TPV"'; then
            # jq's "//" operator provides a default value of 0 if '.speed' is null.
            speed=$(echo "$line" | jq '(.speed // 0) | floor')
            printf "Speed: %s km/h" "$speed" > "$SPEED_FILE"
        fi
    done) >/dev/null 2>&1 &
    echo $! > "$SPEED_READER_PID"
    echo "Speed reader launched with PID $(cat "$SPEED_READER_PID")."
	sleep 5
}

start_speedsender() {
	echo "Launching FFmpeg in background..."
	$FFMPEG_CMD -y -f lavfi -i testsrc=size=320x180:rate=30 \
		-vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:fontsize=30:fontcolor=white:box=1:boxcolor=black@0.5:x=10:y=10:textfile='$SPEED_FILE':reload=1" \
		-c:v libx264 -preset ultrafast -tune zerolatency -crf 23 -f rtsp "${RTSP_URL}_gps" >/dev/null 2>"$SPEED_LOG" &
    echo $! > "$SPEED_PID"

    sleep 1
    echo "FFmpeg launched in background. PID saved to $SPEED_PID."
}

case "$1" in
    start)
        stop_speedsender
		stop_speedreader
		stop_gpsd
        start_gpsd || { echo "[FATAL] Could not start gpsd daemon. Aborting."; exit 1; }
        start_speedreader
        start_speedsender
        ;;
    stop)
        stop_speedsender
		stop_speedreader
		stop_gpsd
        ;;
    status)
        status_gpsd
		status_speedreader
		status_speedsender
        ;;
    *)
		status_gpsd
		status_speedreader
		status_speedsender
		echo "Usage: $0 {start|stop|status}"
        ;;
esac

exit 0
