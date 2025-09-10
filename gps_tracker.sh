#!/bin/bash

dedicated_user=$(ls -ld /opt/VLXframeflow | awk '{print $3}')
if [ "$(id -u)" -eq 0 ]; then
  echo "[ERR] Please launch this script with the dedicated user."
  echo "Never, never use root when not necessaire."
  exit 1
elif [ "$USER" != "$dedicated_user" ]; then
	echo "Only $dedicated_user can correctly execute this script."
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PID_FILE="$SCRIPT_DIR/gps_tracker.pid"
LOG_FILE="$SCRIPT_DIR/gps_tracker.log"
GPSPORT=1198
device=/dev/$(dmesg | grep -E 'tty(ACM|USB)[0-9]+' | grep -v 'disconnect' | tail -n 1 | grep -o 'tty[A-Z]*[0-9]*')
### check if gpsd is running
### if any problem kill it

GPSD=/usr/sbin/gpsd

start() {
    if [ -f "$PID_FILE" ]; then
        echo "Process for camera $1 seems to be already running. Check with 'status'."
        exit 1
    fi
	
	GPSD_CMD="$GPSD -P $PID_FILE -D5 -N -n -S $GPSPORT $device"
	echo "Launching gpsd in background..."
    $GPSD_CMD >/dev/null 2>"$LOG_FILE" &
    echo $! > "$PID_FILE"

    sleep 1
    echo "gpsd launched in background. PID saved to $PID_FILE."
	echo "You can try to get speed with: gpspipe -w 127.0.0.1:1198 | grep -o '\"speed\":[0-9]*\.[0-9]*' "
}

stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "[ERR] PID file not found"
	return
    fi

    echo "Killing gpsd..."
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

case "$1" in
    start)
		status
    	start
		status
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    *)
		status
		echo "Usage: $0 {start|stop|status}"
        ;;
esac

exit 0

