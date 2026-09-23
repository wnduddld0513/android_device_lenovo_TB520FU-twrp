#!/usr/bin/env bash
# Extract the stock TB520FU firmware and copy the vendor blobs TWRP needs for
# decryption (qseecomd, keymint, gatekeeper, ...) into recovery/root/vendor.
# The committed blobs come from ZUI 17.5.10.362; only re-run this when moving
# to another firmware. Needs erofs-utils (fsck.erofs), e2fsprogs, lz4, cpio.
#
# usage: bash device/lenovo/TB520FU/tools/extract_blobs.sh <rom_dir>
#   rom_dir: unpacked QFIL/EDL firmware (rawprogram*.xml, super_*.img,
#            vendor_boot.img, recovery.img)
set -euo pipefail

TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TWRP_DIR=$(cd "$TREE/../../.." && pwd)
ROM=${1:?usage: extract_blobs.sh <rom_dir>}
WORK=$TWRP_DIR/out/tb520fu_extract
ROOT=$TREE/recovery/root
UNPACK="python3 $TWRP_DIR/system/tools/mkbootimg/unpack_bootimg.py"
REPORT=$WORK/out/extract_report.txt

mkdir -p "$WORK/out"
: > "$REPORT"
log() { echo "$*" | tee -a "$REPORT"; }

# ---------------------------------------------------------------- partitions
log "==> logical partitions from super pieces"
python3 "$TREE/tools/extract_super.py" "$ROM" "$WORK/parts" vendor vendor_dlkm odm system_dlkm | tee -a "$REPORT"

extract_fs() { # img dir
    local img=$1 dir=$2
    rm -rf "$dir"; mkdir -p "$dir"
    if [ "$(xxd -s 1024 -l 4 -p "$img")" = "e2e1f5e0" ]; then
        fsck.erofs --extract="$dir" --no-preserve "$img" >/dev/null
    else
        debugfs -R "rdump / $dir" "$img" >/dev/null 2>&1
    fi
}
for p in vendor vendor_dlkm odm system_dlkm; do
    log "   extracting $p"
    extract_fs "$WORK/parts/$p.img" "$WORK/$p"
done
V=$WORK/vendor

# ------------------------------------------------------------ boot images
log "==> vendor_boot / stock recovery"
rm -rf "$WORK/boot"; mkdir -p "$WORK/boot"
$UNPACK --boot_img "$ROM/vendor_boot.img" --out "$WORK/boot/vendor_boot" > "$WORK/boot/vendor_boot.txt"
$UNPACK --boot_img "$ROM/recovery.img"    --out "$WORK/boot/recovery"    > "$WORK/boot/recovery.txt"
for d in vendor_boot recovery; do
    rd=$(ls "$WORK/boot/$d"/*ramdisk* 2>/dev/null | head -n1)
    mkdir -p "$WORK/boot/$d/root"
    (cd "$WORK/boot/$d/root" && lz4 -dc "$rd" 2>/dev/null | cpio -idm --quiet 2>/dev/null || true)
done

# ------------------------------------------------------------ module info
log "==> kernel modules"
for f in modules.load modules.load.recovery; do
    [ -f "$WORK/boot/vendor_boot/root/lib/modules/$f" ] && \
        log "   vendor_boot $f: $(wc -l < "$WORK/boot/vendor_boot/root/lib/modules/$f") entries"
done
log "   touch / panel related modules:"
find "$WORK/boot/vendor_boot/root/lib/modules" "$WORK/vendor_dlkm" -name '*.ko' 2>/dev/null \
    | grep -iE 'nvt|novatek|nt365|touch|_ts|goodix|panel|msm_drm|backlight' | sed 's/^/     /' | tee -a "$REPORT" || true
grep -hiE 'nvt|novatek|touch|_ts' "$WORK/boot/vendor_boot/root/lib/modules/modules.load.recovery" 2>/dev/null \
    | sed 's/^/     in modules.load.recovery: /' | tee -a "$REPORT" || true

# ------------------------------------------------------------ fstab / props
log "==> stock fstab (/data, /metadata)"
FSTAB=$(ls "$V"/etc/fstab.* 2>/dev/null | head -n1 || true)
[ -n "$FSTAB" ] && grep -E '[[:space:]]/(data|metadata)[[:space:]]' "$FSTAB" | tee -a "$REPORT"
log "==> security-level props"
grep -rhE 'gatekeeper|keymint|is_security_level_spu|spu' "$V"/build.prop "$V"/etc/*.prop 2>/dev/null | sort -u | tee -a "$REPORT" || true

# ------------------------------------------------------------ blobs
BLOBS=(
    bin/qseecomd
    bin/spdaemon
    bin/sec_nvm
    bin/hlosminkdaemon
    bin/hw/android.hardware.security.keymint-service-qti
    bin/hw/android.hardware.security.keymint-service-spu-qti
    bin/hw/android.hardware.gatekeeper-service-qti
    bin/hw/android.hardware.gatekeeper-service-spu-qti
    bin/hw/android.hardware.weaver-service-spu-qti
    bin/hw/android.hardware.boot-service.qti
    bin/hw/android.hardware.health-service.qti
    etc/gpfspath_oem_config.xml
    etc/ueventd.rc
    lib64/libQSEEComAPI.so
    lib64/libqtikeymint.so
    lib64/libspukeymint.so
    lib64/libspcom.so
    lib64/libGPreqcancel.so
    lib64/libGPreqcancel_svc.so
    lib64/libkeymasterdeviceutils.so
    lib64/libkeymasterutils.so
    lib64/libqcbor.so
    lib64/librpmb.so
    lib64/libssd.so
    lib64/libdiag.so
    lib64/libdrmfs.so
    lib64/libdrmtime.so
    lib64/libtime_genoff.so
    lib64/libops.so
    lib64/libminkdescriptor.so
    lib64/libminksocket_vendor.so
    # dlopen()ed by qseecomd listeners (not in any NEEDED list; without them
    # qseecomd exits 255 and no TZ listener gets registered)
    lib64/libgpt.so
    lib64/libqisl.so
    lib64/libspl.so
    lib64/hw/libqtigatekeeper.so
    lib64/hw/libspuqtigatekeeper.so
)
# init rc + vintf fragments matching the binaries above
RC_PATTERN='qseecomd|spdaemon|sec_nvm|minkdaemon|keymint|gatekeeper|weaver|boot-service|health-service'

log "==> copying blobs to $ROOT/vendor"
copy_one() { # relpath
    local rel=$1
    if [ -e "$V/$rel" ]; then
        install -D -m "$( [[ $rel == bin/* ]] && echo 755 || echo 644 )" "$V/$rel" "$ROOT/vendor/$rel"
        return 0
    fi
    log "   MISSING: vendor/$rel"; return 1
}
for b in "${BLOBS[@]}"; do copy_one "$b" || true; done

for rc in $(ls "$V/etc/init" | grep -E "$RC_PATTERN" || true); do
    install -D -m 644 "$V/etc/init/$rc" "$ROOT/vendor/etc/init/$rc"
    # run every service in the recovery domain
    awk '{print} /^service /{print "    seclabel u:r:recovery:s0"}' "$V/etc/init/$rc" \
        | grep -v '^[[:space:]]*seclabel u:r:[^r]' > "$ROOT/vendor/etc/init/$rc"
done
for x in $(ls "$V/etc/vintf/manifest" 2>/dev/null | grep -E "$RC_PATTERN|qseecom|secureprocessor|spu" || true); do
    install -D -m 644 "$V/etc/vintf/manifest/$x" "$ROOT/vendor/etc/vintf/manifest/$x"
done
# gatekeeper / weaver / strongbox keymint are declared in the SKU manifest
install -D -m 644 "$V/etc/vintf/manifest_pineapple.xml" "$ROOT/vendor/etc/vintf/manifest.xml"

# Recovery adjustments: services are started from init.recovery.qcom.rc once
# persist is mounted, so drop the stock early/conditional start triggers.
INIT=$ROOT/vendor/etc/init
strip_block() { # file header-regex : delete an "on ..." block whose header matches
    awk -v re="$2" '
        /^on / { skip = ($0 ~ re) }
        /^service / { skip = 0 }
        !skip' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
[ -f "$INIT/qseecomd.rc" ] && strip_block "$INIT/qseecomd.rc" '^on init'
[ -f "$INIT/android.hardware.security.keymint-service-qti.rc" ] && \
    strip_block "$INIT/android.hardware.security.keymint-service-qti.rc" '^on init'
[ -f "$INIT/init.spdaemon.rc" ] && strip_block "$INIT/init.spdaemon.rc" '^on '
if [ -f "$INIT/android.hardware.health-service.qti.rc" ]; then
    # drop the off-mode charger service
    awk '/^service vendor.charger /{skip=1; next} /^(service|on) /{skip=0} !skip' \
        "$INIT/android.hardware.health-service.qti.rc" > "$INIT/h.tmp" && \
        mv "$INIT/h.tmp" "$INIT/android.hardware.health-service.qti.rc"
fi

# prepdecrypt.sh (sets OS version / patch level props for keymint)
PREP=$TWRP_DIR/device/qcom/twrp-common/crypto/system/bin/prepdecrypt.sh
[ -f "$PREP" ] || { rm -rf /tmp/twrp-common; git clone -q --depth=1 -b android-14.1 \
    https://github.com/TeamWin/android_device_qcom_twrp-common /tmp/twrp-common; \
    PREP=/tmp/twrp-common/crypto/system/bin/prepdecrypt.sh; }
install -D -m 755 "$PREP" "$ROOT/system/bin/prepdecrypt.sh"

# The gatekeeper service NEEDs libqtigatekeeper.so, but its rc sets no
# LD_LIBRARY_PATH and the default search path has no /vendor/lib64/hw
for l in libqtigatekeeper.so libspuqtigatekeeper.so; do
    [ -f "$ROOT/vendor/lib64/hw/$l" ] && install -D -m 644 "$ROOT/vendor/lib64/hw/$l" "$ROOT/vendor/lib64/$l"
done

# touch firmware
for fw in $(ls "$V/firmware" 2>/dev/null | grep -iE 'nvt|novatek|nt365|_ts_' || true); do
    install -D -m 644 "$V/firmware/$fw" "$ROOT/vendor/firmware/$fw"
done

# resolve NEEDED libs recursively (vendor libs only; system libs come from TWRP)
log "==> resolving NEEDED vendor libraries"
changed=1
while [ $changed = 1 ]; do
    changed=0
    while IFS= read -r elf; do
        for lib in $(readelf -d "$elf" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
            [ -e "$ROOT/vendor/lib64/$lib" ] && continue
            if [ -e "$V/lib64/$lib" ]; then
                install -D -m 644 "$V/lib64/$lib" "$ROOT/vendor/lib64/$lib"
                log "   + vendor/lib64/$lib (needed by ${elf##*/})"
                changed=1
            fi
        done
    done < <(find "$ROOT/vendor" -type f \( -path '*/bin/*' -o -name '*.so' \))
done

log "==> blob tree size: $(du -sh "$ROOT/vendor" | cut -f1)"
log "report: $REPORT"
