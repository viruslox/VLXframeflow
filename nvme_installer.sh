#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "[ERR]: This script requires root privileges. Please run it as root or use sudo."
    exit 1
fi

echo "[INFO]: Enable user root: Set the root user password."
passwd root
systemctl enable --now ssh

mapfile -t DEVICES < <(lsblk -p -d -n -o NAME | grep 'nvme')

if [ ${#DEVICES[@]} -eq 0 ]; then
    echo "[INFO]: No NVMe devices found. Exit."
    exit 0
fi

echo "The following NVMe drives were found. Please select one."
echo "Please note that proceeding will WIPE THE ENTIRE SELECTED DRIVE."
echo ""

for i in "${!DEVICES[@]}"; do
    echo "[$i] ${DEVICES[$i]}"
done
echo "[X] Cancel operation and Quit"
echo ""
read -p "Enter your choice and press <Enter>: " CHOICE

if [[ "$CHOICE" =~ ^[xX]$ ]]; then
    echo "[INFO]: Operation cancelled by user. Exit."
    exit 0
fi

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -ge "${#DEVICES[@]}" ]; then
    echo "[ERR]: Invalid selection. Please enter a number from the list."
    exit 1
fi

if [ ! -b "${DEVICES[$CHOICE]}" ]; then
    echo "[ERR]: Unidentified error. Exit"
    exit 1
else
    CHOSEN_DEVICE="${DEVICES[$CHOICE]}"
    CURRENT_LAYOUT=$(sfdisk -d "$CHOSEN_DEVICE" 2>/dev/null)
	linuxtype_count=$(echo "$CURRENT_LAYOUT" | grep -c 'type=0FC63DAF-8483-4772-8E79-3D69D8477DE4')
fi

if echo "$CURRENT_LAYOUT" | grep -q 'label: gpt' && \
   echo "$CURRENT_LAYOUT" | grep -q 'type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B' && \
   echo "$CURRENT_LAYOUT" | grep -q 'type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F' && \
   [ "$linuxtype_count" -ge 3 ]; then

    echo "Found VLXframeflow compatible partition scheme in $CHOSEN_DEVICE."
    read -r -p "Do You wish to skeep re-partitioning and keep /home data? (y/N) " response
    
    case "$response" in
        [yY])
            SKIP_PARTITIONING=true
            ;;
        *)
            SKIP_PARTITIONING=false
            ;;
    esac
else
    SKIP_PARTITIONING=false
fi

while mount | grep -q "${CHOSEN_DEVICE}"; do
    echo "Found active mounts. Unmounting..."
    for mount_point in $(mount | grep "${CHOSEN_DEVICE}" | awk '{print $3}' | sort -r); do
        echo "Attempting to unmount: $mount_point"
        umount "$mount_point"
    done
    sleep 1
done

if [ "$SKIP_PARTITIONING" = false ]; then
    read -p "We are about to COMPLETELY WIPE $CHOSEN_DEVICE type 'ok' and press <Enter>: " FINAL_CONFIRM
    if [ "$FINAL_CONFIRM" != "ok" ]; then
        echo "[INFO]: Operation cancelled by user."
        exit 0
    fi

	echo "--> Starting non-interactive partitioning on $CHOSEN_DEVICE..."
    sfdisk "$CHOSEN_DEVICE" << EOF
label: gpt
size=1G,type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B,name="EFI System"
size=1G,type=0FC63DAF-8483-4772-8E79-3D69D8477DE4,name="Linux boot"
size=4G,type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F,name="Linux swap"
size=44G,type=0FC63DAF-8483-4772-8E79-3D69D8477DE4,name="Linux root"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4,name="Linux home"
EOF
    if [ $? -ne 0 ]; then
        echo "[ERR]: Partitioning $CHOSEN_DEVICE failed."
        exit 1
    fi
    # Force kernel to re-read partition table
    partprobe "$CHOSEN_DEVICE"
    sleep 2
    echo "[OK]: Partitioning of $CHOSEN_DEVICE complete."
fi

echo "Formatting partitions"
mkfs.vfat -F 32 -n EFI "${CHOSEN_DEVICE}p1" || { echo "[ERR]: Filesystem creation failed on p1 [vfat]"; exit 1; }
mkfs.ext4 -F -L boot "${CHOSEN_DEVICE}p2"   || { echo "[ERR]: Filesystem creation failed on p2 [ext4]"; exit 1; }
mkfs.ext4 -F -L root "${CHOSEN_DEVICE}p4"   || { echo "[ERR]: Filesystem creation failed on p4 [ext4]"; exit 1; }
mkswap -f -L swap "${CHOSEN_DEVICE}p3"      || { echo "[ERR]: Swap creation failed on p3"; exit 1; }
if [ "$SKIP_PARTITIONING" = false ]; then
    mkfs.ext4 -F -L home "${CHOSEN_DEVICE}p5" || { echo "[ERR]: Filesystem creation failed on p5 [ext4]"; exit 1; }
fi
echo "[OK]: Formatting complete:"

lsblk -f $CHOSEN_DEVICE
echo "[INFO]: Starting OS installation in $CHOSEN_DEVICE"
TEMP_MOUNT="/mnt/temp"
mkdir -p "$TEMP_MOUNT"
mount "${CHOSEN_DEVICE}p4" "$TEMP_MOUNT"
mkdir -p "$TEMP_MOUNT/home"
mount "${CHOSEN_DEVICE}p5" "$TEMP_MOUNT/home"
mkdir -p "${TEMP_MOUNT}/boot"
mount "${CHOSEN_DEVICE}p2" "${TEMP_MOUNT}/boot"
mkdir -p "${TEMP_MOUNT}/boot/efi" "${TEMP_MOUNT}/boot/firmware"
mount "${CHOSEN_DEVICE}p1" "${TEMP_MOUNT}/boot/efi"
mount "${CHOSEN_DEVICE}p1" "${TEMP_MOUNT}/boot/firmware"

echo "[INFO] Cloning the current OS to $CHOSEN_DEVICE."
rsync_opts=(
    -aAXv
    --delete
    --exclude=/dev/*
    --exclude=/proc/*
    --exclude=/sys/*
    --exclude=/tmp/*
    --exclude=/run/*
    --exclude=/mnt/*
    --exclude=/media/*
    --exclude=/lost-found
)
if [ "$SKIP_PARTITIONING" = true ]; then
    echo "[INFO]: Preserving /home as requested."
    rsync_opts+=(--exclude=/home/*)
fi
rsync "${rsync_opts[@]}" / "$TEMP_MOUNT/"
rsync_exit_code=$?
if [ $rsync_exit_code -ne 0 ]; then
    if [ $rsync_exit_code -eq 23 ] || [ $rsync_exit_code -eq 24 ]; then
	    echo "[WARN]: OS cloning with rsync failed with exit code $rsync_exit_code."
		echo "This indicates a partial transfer. Some files were not copied due to errors, it's still ok ignore those errors."
    else
	    echo "[ERR]: OS cloning with rsync failed with exit code $rsync_exit_code."
    	exit 1
	 fi
fi

sync
echo "[OK]: OS cloning complete."

# Get UUIDs reliably
P1UUID=$(lsblk -f -n -o UUID "${CHOSEN_DEVICE}p1")
P2UUID=$(lsblk -f -n -o UUID "${CHOSEN_DEVICE}p2")
P3UUID=$(lsblk -f -n -o UUID "${CHOSEN_DEVICE}p3")
P4UUID=$(lsblk -f -n -o UUID "${CHOSEN_DEVICE}p4")
P5UUID=$(lsblk -f -n -o UUID "${CHOSEN_DEVICE}p5")

umount "${TEMP_MOUNT}/boot/firmware"
rmdir "${TEMP_MOUNT}/boot/firmware"
cd $TEMP_MOUNT/boot/
ln -sf efi firmware

cd $TEMP_MOUNT
cp -p ${TEMP_MOUNT}/boot/efi/cmdline.txt ${TEMP_MOUNT}/boot/efi/cmdline.txt.BK
echo "console=serial0,115200 console=tty1 root=UUID=$P4UUID rootfstype=ext4 fsck.repair=yes rootwait nosplash debug --verbose cfg80211.ieee80211_regdom=IT" consoleblank=0 > $TEMP_MOUNT/boot/efi/cmdline.txt

# Create new fstab
FSTAB_FILE="${TEMP_MOUNT}/etc/fstab"
echo "proc /proc proc defaults 0 0" > "$FSTAB_FILE"
echo "UUID=$P1UUID /boot/efi vfat defaults 0 2" >> "$FSTAB_FILE"
echo "UUID=$P2UUID /boot ext4 defaults 0 2" >> "$FSTAB_FILE"
echo "UUID=$P4UUID / ext4 errors=remount-ro 0 1" >> "$FSTAB_FILE"
echo "UUID=$P5UUID /home ext4 defaults 0 2" >> "$FSTAB_FILE"
echo "UUID=$P3UUID none swap sw 0 0" >> "$FSTAB_FILE"

# Disable SUDO, we'll not use it
rm -fv ${TEMP_MOUNT}/etc/sudoers.d/*

cd ~
sync
while mount | grep -q "${CHOSEN_DEVICE}"; do
    echo "Found active mounts. Unmounting..."
    for mount_point in $(mount | grep "${CHOSEN_DEVICE}" | awk '{print $3}' | sort -r); do
        echo "Attempting to unmount: $mount_point"
        umount "$mount_point"
    done
    sleep 1
done
sync

echo "[OK]: OS Installation complete."
echo "You can now shut down, remove the SD card and boot from the NVMe drive."

exit 0
