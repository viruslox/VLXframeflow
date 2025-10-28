#!/bin/bash

PROFILE_FILE=$(find $HOME -name '.frameflow_profile' 2>/dev/null)
if [ -f "$PROFILE_FILE" ]; then
  source "$PROFILE_FILE"
fi
if [ -z "$VLXlogs_DIR" ]; then
  $VLXlogs_DIR="/opt/VLXflowlogs"
fi

## Clean suite logs
find $VLXlogs_DIR -type f -mtime +15 -exec rm -v {} \;

## clean system logs
find /var/log -type f -mtime +30 -exec rm -v {} \;

## save list of installed packages
dpkg --get-selections | awk '{print $1}' | grep -vE '^(linux-image|linux-headers|linux-firmware|firmware|grub|nvidia|virtualbox|base-files|desktop|-desktop)' >/home/pkg.list

exit 0
