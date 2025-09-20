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

if [ -z "$VLXsuite_DIR" ]; then
	VLXsuite_DIR="/opt/VLXframeflow"
fi
if [ -z "$VLXlogs_DIR" ]; then
	$VLXlogs_DIR="/opt/VLXflowlogs"
fi

# if zero means not enabled; 1 means enable only the first device found, 2 only the first 2 devices found...
if [ -z "$ENABLED_DEVICES" ]; then
    ENABLED_DEVICES=1
elif [[ "$ENABLED_DEVICES" -eq 0 ]]; then
    echo "[ERR] The tools is configured as not enabled"
    exit 1
fi

if [ -z "$RTSP_URL" ]; then
    echo "[ERR] RTSP_URL is not set in ~/.frameflow_profile"
    exit 1
fi
if [ -z "$AUDIODEV" ]; then
    echo "[ERR] AUDIODEV is not set in ~/.frameflow_profile"
    exit 1
else
    AUDIODEV=$(arecord -l | grep "${AUDIODEV}" | cut -d ' ' -f 3)
fi

if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "[ERR] Sorry, intergers only"
    exit 1
elif [[ "$1" -eq 0 || "$1" -gt "$ENABLED_DEVICES" ]]; then
    echo "[ERR] You can't use a not enabled device."
    echo "Usage: $0 {1|...|$ENABLED_DEVICES} {start|stop|status}"
    exit 1
fi

PID_FILE="$VLXlogs_DIR/ffmpeg_stream_$1.pid"
LOG_FILE="$VLXlogs_DIR/ffmpeg_stream_$1.log"

FFMPEG_CMD=$(which ffmpeg)

start() {
    if [ -f "$PID_FILE" ]; then
        echo "Process for camera $1 seems to be already running. Check with 'status'."
        exit 1
    fi

	CAMERA=$(($1 - 1))
	#videodevlist=$(v4l2-ctl --list-devices | grep -A1 'usb-xhci' | grep '/dev/video' | head -n1 | xargs)
	mapfile -t videodevlist < <(v4l2-ctl --list-devices | grep -A1 'usb-xhci' | grep '/dev/video')
	echo "Found input video devices: ${videodevlist[@]}"
    
    if [[ "$CAMERA" -eq 0 ]] && [[ -n "${AUDIODEV}" ]]; then
        AUDIOCAM="-f alsa -i hw:CARD=${AUDIODEV}"
        AUDIOCOD="-c:a aac -b:a 128k"
    else
        unset AUDIOCAM AUDIOCOD
    fi
    
	FFMPEG_CMD="$FFMPEG_CMD -f v4l2 -framerate 30 -video_size 1920x1080 -i ${videodevlist[$CAMERA]} ${AUDIOCAM} -c:v libx264 -pix_fmt yuv420p -preset superfast -b:v 600k ${AUDIOCOD} -f rtsp ${RTSP_URL}_$1"

	if [ -z "${videodevlist[$CAMERA]}" ]; then
		echo "[ERR] Video device ${videodevlist[$CAMERA]} not found!"
		exit 1
	fi

	echo "Launching FFmpeg in background..."
    $FFMPEG_CMD >/dev/null 2>"$LOG_FILE" &
    echo $! > "$PID_FILE"

    sleep 1
    echo "FFmpeg launched in background. PID saved to $PID_FILE."
}

stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "[ERR] PID file not found"
	return
    fi

    echo "Killing FFmpeg..."
    kill $(cat "$PID_FILE")
    rm "$PID_FILE"
    echo "Done."
}

status() {
    if [ ! -f "$PID_FILE" ]; then
        echo "[INFO] PID file not found"
        return
    fi

    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
        echo "Already running with PID: $PID"
        echo "Check logs: tail -f $LOG_FILE"
    else
        echo "[ERR] PID file found but process does not exist, removing PID file" 
	rm $PID_FILE
    fi
}

case "$2" in
    start)
	status
        start $1
	status
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {1|...|$ENABLED_DEVICES} {start|stop|status}"
        exit 1
        ;;
esac

exit 0
