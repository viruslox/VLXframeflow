#!/bin/bash

## save list of installed packages
dpkg --get-selections | awk '{print $1}' | grep -vE '^(linux-image|linux-headers|linux-firmware|firmware|grub|nvidia|virtualbox|base-files|desktop|-desktop)' >/home/pkg.list

## clean logs
find /var/log -type f -mtime +30 -exec rm -v {} \;

exit 0
