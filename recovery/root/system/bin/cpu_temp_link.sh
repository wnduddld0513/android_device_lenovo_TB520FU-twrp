#!/system/bin/sh
# thermal_zone numbering changes between boots (modules load in parallel), so
# find the CPU sensor by type and expose it at a fixed path for TWRP
# (TW_CUSTOM_CPU_TEMP_PATH := /tmp/cpu_temp).

# run via init "exec" (blocking): thermal zones come from first-stage modules
# and already exist, so only wait briefly
for i in $(seq 1 5); do
    for z in /sys/class/thermal/thermal_zone*; do
        if [ "$(cat "$z/type" 2>/dev/null)" = "cpuss-0" ]; then
            ln -sf "$z/temp" /tmp/cpu_temp
            exit 0
        fi
    done
    sleep 1
done
