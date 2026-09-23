#!/system/bin/sh

slot=`getprop ro.boot.slot_suffix`
for i in `seq 1 100`; do
    log -t load-adsp.sh "Load adsp try $i"
    mkdir /vendor/firmware_mnt
    log -t load-adsp.sh mount: `mount -t vfat -o ro /dev/block/by-name/modem$slot /vendor/firmware_mnt 2>&1`
    # Load ADSP firmware for PMIC
    echo 1 > /sys/kernel/boot_adsp/boot
    if [ -d /sys/class/power_supply/battery ]; then
        log -t load-adsp.sh "Load adsp done"
        break
    fi
    sleep 1
done
umount /vendor/firmware_mnt
setprop vendor.adsp_loaded 1
