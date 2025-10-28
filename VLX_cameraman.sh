#!/bin/bash

dedicated_user=$(ls -ld /opt/VLXframeflow | awk '{print $3}')
if [ "$(id -u)" -eq 0 ]; then
  echo "[ERR] Please launch this script with the dedicated user: $dedicated_user"
  echo "Never, never use root when not necessaire."
  exit 1
elif [ "$USER" != "$dedicated_user" ]; then
    echo "[ERR] Only $dedicated_user can correctly execute this script."
    exit 1
fi

if [ -f ~/.frameflow_profile ]; then
    source ~/.frameflow_profile
else
    echo "[ERR] ~/.frameflow_profile not found."
    exit 1
fi

VLXsuite_DIR="${VLXsuite_DIR:-/opt/VLXframeflow}"
VLXlogs_DIR="${VLXlogs_DIR:-/opt/VLXflowlogs}"

# if zero means not enabled; 1 means enable only the first device found, 2 only the first 2 devices found...
ENABLED_DEVICES="${ENABLED_DEVICES:-1}"
if [[ "$ENABLED_DEVICES" -eq 0 ]]; then
    echo "[ERR] The tools is configured as not enabled"
    exit 1
fi

case "$3" in
    rtsp)
        if [ -z "$RTSP_URL" ]; then
            echo "[ERR] RTSP_URL is not set in ~/.frameflow_profile"
            exit 1
        else
            STRURL="$RTSP_URL"
            STRMODE="rtsp"
        fi
        ;;
    srt | *)
        if [ -z "$SRT_URL" ]; then
            echo "[ERR] SRT_URL is not set in ~/.frameflow_profile"
            exit 1
        else
            STRURL="$SRT_URL"
            STRMODE="mpegts"
        fi
        ;;
esac

if [ -z "$AUDIODEV" ]; then
    echo "[ERR] AUDIODEV is not set in ~/.frameflow_profile, looking for any USB audio source"
    AUDIODEV='card.*USB'
fi
AUDIODEV_HW=$(arecord -l | grep -m1 "card .*\[${AUDIODEV}\]" | sed -n 's/card \([0-9]\+\): .*/\1/p')

if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "[ERR] Sorry, integers only"
    exit 1
elif [[ "$1" -eq 0 || "$1" -gt "$ENABLED_DEVICES" ]]; then
    echo "[ERR] You can't use a not enabled device."
    echo "Usage: $0 {1|...|$ENABLED_DEVICES} {start|stop|status}"
    exit 1
fi

PID_FILE="$VLXlogs_DIR/ffmpeg_stream_$1.pid"
LOG_FILE="$VLXlogs_DIR/ffmpeg_stream_$1.log"

FFMPEG_PATH=$(which ffmpeg)
MPTCPIZE_PATH=$(which mptcpize)

if [ -z "$FFMPEG_PATH" ]; then echo "[ERR] ffmpeg executable not found in PATH"; exit 1; fi
if [ -z "$MPTCPIZE_PATH" ]; then echo "[ERR] mptcpize executable not found in PATH"; exit 1; fi



start() {
    local CAMERA_ID="$1"
    if [ -f "$PID_FILE" ]; then
        echo "Process for camera $CAMERA_ID seems to be already running. Check with 'status'."
        exit 1
    fi

    local CAMERA_INDEX=$((CAMERA_ID - 1))
    mapfile -t videodevlist < <(v4l2-ctl --list-devices | grep -A1 'usb' | grep --line-buffered '/dev/video' | sed 's/^[ \t]*//')
    
    if [ ${#videodevlist[@]} -eq 0 ]; then
        echo "[ERR] No '/dev/video*' devices found."
        exit 1
    fi
    echo "Found input video devices: ${videodevlist[@]}"

    local VIDEO_DEVICE="${videodevlist[$CAMERA_INDEX]}"
    if [ -z "$VIDEO_DEVICE" ]; then
        echo "[ERR] Video device for camera $CAMERA_ID (index $CAMERA_INDEX) not found!"
        exit 1
    fi

    local -a FFMPEG_CMD_ARRAY=(
        "$MPTCPIZE_PATH" "run" "$FFMPEG_PATH"
        "-f" "v4l2"
        "-framerate" "30"
        "-video_size" "1920x1080"
        "-i" "$VIDEO_DEVICE"
    )
    
    if [[ "$CAMERA_INDEX" -eq 0 ]] && [[ -n "${AUDIODEV_HW}" ]]; then
        echo "Adding audio input from hw:CARD=${AUDIODEV_HW}"
        FFMPEG_CMD_ARRAY+=("-f" "alsa" "-i" "hw:CARD=${AUDIODEV_HW}")
        FFMPEG_CMD_ARRAY+=("-c:a" "aac" "-b:a" "128k")
    fi
    
    FFMPEG_CMD_ARRAY+=(
        "-c:v" "libx264"
        "-preset" "ultrafast"
        "-tune" "zerolatency"
        "-f" "${STRMODE}"
        "${STRURL}_${CAMERA_ID}"
    )

    echo "Launching FFmpeg in background..."
    echo "Executing command: ${FFMPEG_CMD_ARRAY[@]}"

    "${FFMPEG_CMD_ARRAY[@]}" >/dev/null 2>"$LOG_FILE" &
    echo $! > "$PID_FILE"

    sleep 1
    echo "FFmpeg launched in background. PID saved to $PID_FILE."
}

stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "[INFO] PID file not found. Nothing to stop."
        return
    fi
    local PID=$(cat "$PID_FILE")
    echo "Killing FFmpeg process with PID $PID..."
    # Kill the process, ignore error if it's already gone
    kill "$PID" 2>/dev/null || true
    rm "$PID_FILE"
    echo "Done."
}

status() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Status: Not running (PID file not found)."
        return
    fi

    local PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null; then
        echo "Status: Already running with PID: $PID"
        echo "Check logs: tail -f $LOG_FILE"
    else
        echo "[WARN] PID file found but process does not exist, removing stale PID file."
        rm "$PID_FILE"
    fi
}

case "$2" in
    start)
        status
        start "$1"
        sleep 1
        status
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {1|...|$ENABLED_DEVICES} {start|stop|status} {srt|rtsp}"
        exit 1
        ;;
esac

exit 0
