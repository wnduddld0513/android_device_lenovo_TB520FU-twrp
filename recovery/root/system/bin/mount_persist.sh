#!/system/bin/sh
# Make sure /mnt/vendor/persist is mounted. qseecomd's drmfs listener
# (secure file system used by the keymint TA) checks /proc/mounts for it and
# otherwise fails with "persist partition is not mounted, dispatch failed",
# which leaves keymint's TZ call blocked on a callback forever.
# TWRP itself only mounts /persist briefly (time fixup) and unmounts it again.

MNT=/mnt/vendor/persist
DEV=/dev/block/bootdevice/by-name/persist
[ -e "$DEV" ] || DEV=/dev/block/by-name/persist

mkdir -p "$MNT"
if grep -q " $MNT " /proc/mounts; then
    log -t mount_persist "$MNT already mounted"
elif mount -t ext4 -o noatime,nosuid,nodev,barrier=1 "$DEV" "$MNT"; then
    log -t mount_persist "mounted $DEV on $MNT"
else
    log -t mount_persist "ERROR: mount $DEV on $MNT failed"
    exit 0
fi

# Expose the same mount at /persist for TWRP (time fixup, backups, file
# manager). A second independent mount of the partition by TWRP fails with
# "Device or resource busy"; with the bind mount present TWRP sees /persist
# as already mounted and never tries.
mkdir -p /persist
if ! grep -q " /persist " /proc/mounts; then
    mount --bind "$MNT" /persist && log -t mount_persist "bind-mounted $MNT on /persist"
fi

mkdir -p "$MNT/secnvm" "$MNT/spudc" "$MNT/iar_db"
chown system:system "$MNT/secnvm" "$MNT/spudc" "$MNT/iar_db"
chmod 0770 "$MNT/secnvm" "$MNT/spudc" "$MNT/iar_db"
