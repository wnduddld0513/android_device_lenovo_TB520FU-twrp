#!/usr/bin/env bash
# Sign the built TWRP recovery.img with the AOSP AVB testkey_rsa4096
# (pubkey sha1 2597c218...), the key a testkey-resigned TB520FU firmware uses
# for vbmeta and its recovery chain, mirroring the stock recovery footer
# layout, then sanity-check the image before it is flashed.
#
# usage: bash device/lenovo/TB520FU/tools/sign.sh [path/to/recovery.img]
# env:   VBMETA=<installed firmware's vbmeta.img>  also verify the recovery
#                                                 chain against it (optional)
#        OUT_DIR=<dir>  where the signed image goes
#                       (default: out/target/product/TB520FU)
set -euo pipefail

TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TWRP_DIR=$(cd "$TREE/../../.." && pwd)
WORK=$TWRP_DIR/out/tb520fu_sign
VBMETA=${VBMETA:-}
WIN=${OUT_DIR:-$TWRP_DIR/out/target/product/TB520FU}
mkdir -p "$WORK/out" "$WIN"
AVBTOOL="python3 $TWRP_DIR/external/avb/avbtool.py"
KEY=$TWRP_DIR/external/avb/test/data/testkey_rsa4096.pem
EXPECT_KEY_SHA1=2597c218aae470a130f61162feaae70afd97f011   # AOSP testkey_rsa4096
PART_SIZE=104857600
FINGERPRINT='Lenovo/TB520FU/TB520FU:14/UKQ1.240826.001/ZUI_17.5.10.362_260719_ROW:user/release-keys'

IN=${1:-$TWRP_DIR/out/target/product/TB520FU/recovery.img}
DATE=$(date +%Y%m%d)
NAME=TWRP-3.7.1_14-TB520FU-$DATE-landscape
OUT=$WORK/out/$NAME.img

echo "==> key check"
$AVBTOOL extract_public_key --key "$KEY" --output "$WORK/out/testkey_rsa4096.avbpubkey"
KSHA=$(sha1sum "$WORK/out/testkey_rsa4096.avbpubkey" | cut -d' ' -f1)
[ "$KSHA" = "$EXPECT_KEY_SHA1" ] || { echo "key sha1 $KSHA != $EXPECT_KEY_SHA1"; exit 1; }
echo "   testkey_rsa4096 pubkey sha1 = $KSHA"

echo "==> sign $IN"
cp "$IN" "$OUT"
$AVBTOOL erase_footer --image "$OUT" 2>/dev/null || true
# Same layout as stock recovery: rollback index 1, location 0 in the footer
# (vbmeta's chain descriptor carries location 1), recovery fingerprint prop.
$AVBTOOL add_hash_footer \
    --image "$OUT" \
    --partition_name recovery \
    --partition_size $PART_SIZE \
    --algorithm SHA256_RSA4096 \
    --key "$KEY" \
    --rollback_index 1 \
    --prop "com.android.build.recovery.fingerprint:$FINGERPRINT"

echo "==> info"
$AVBTOOL info_image --image "$OUT" | tee "$WORK/out/$NAME.avbinfo.txt"

echo "==> boot header check"
python3 "$TWRP_DIR/system/tools/mkbootimg/unpack_bootimg.py" --boot_img "$OUT" --out "$WORK/out/unpack" \
    | grep -E 'boot image header version|kernel size|ramdisk size' | tee -a "$WORK/out/$NAME.avbinfo.txt"
RD=$(ls "$WORK/out/unpack"/ramdisk* | head -n1)
mkdir -p "$WORK/out/unpack/root"
(cd "$WORK/out/unpack/root" && lz4 -dc "$RD" | cpio -idm --quiet 2>/dev/null || true)
# system/etc/vintf/manifest.xml: without a framework manifest servicemanager
# ignores the manifest/ fragments and refuses to register keystore2
for f in system/bin/twrp system/bin/recovery twres/ui.xml vendor/bin/qseecomd \
         system/etc/vintf/manifest.xml system/etc/vintf/manifest/android.system.keystore2-service.xml \
         system/etc/task_profiles.json system/bin/bootstrap/linker64 \
         vendor/bin/hw/android.hardware.security.keymint-service-qti vendor/etc/vintf/manifest.xml; do
    [ -e "$WORK/out/unpack/root/$f" ] && echo "   ramdisk has $f" || echo "   ramdisk MISSING $f"
done

echo "==> ramdisk copies of TWRP libraries are up to date"
PRODUCT_OUT=$TWRP_DIR/out/target/product/TB520FU
stale=0
for l in libminuitwrp.so libguitwrp.so libaosprecovery.so libtwrpinstall.so libtar.so; do
    a=$WORK/out/unpack/root/system/lib64/$l; b=$PRODUCT_OUT/system/lib64/$l
    [ -f "$a" ] && [ -f "$b" ] || continue
    if cmp -s "$a" "$b"; then echo "   OK: $l"; else echo "   STALE: $l (ramdisk copy differs from build output)"; stale=1; fi
done
[ $stale = 0 ] || { echo "   ERROR: rebuild with scripts/build.sh (it clears the recovery staging dir)"; exit 1; }

echo "==> SELinux: recovery domain must be permissive (locked bootloader keeps init enforcing)"
CIL=$(ls "$TWRP_DIR"/out/soong/.intermediates/system/sepolicy/recovery_sepolicy.cil/android_common/*/recovery_sepolicy.cil 2>/dev/null | head -n1)
for d in recovery logd kernel hal_fastboot_default; do
    if [ -n "$CIL" ] && grep -q "(typepermissive $d)" "$CIL"; then
        echo "   OK: (typepermissive $d)"
    else
        echo "   ERROR: $d domain is not permissive in the built policy"; exit 1
    fi
done
# init stays enforcing: it must be able to write the BCB to misc, otherwise it
# cancels "reboot,recovery" and TWRP just restarts
if grep -q 'by-name/misc.*misc_block_device' "$WORK/out/unpack/root/vendor_file_contexts" 2>/dev/null; then
    echo "   OK: misc labeled misc_block_device"
else
    echo "   ERROR: misc has no misc_block_device label (sepolicy/file_contexts)"; exit 1
fi

echo "==> framework VINTF fragments must all be type=framework"
bad_frag=$(grep -l 'type="device"' "$WORK/out/unpack/root/system/etc/vintf/manifest/"*.xml 2>/dev/null || true)
if [ -n "$bad_frag" ]; then
    echo "   ERROR: device-type fragment(s) in system vintf (servicemanager drops the framework manifest):"
    echo "$bad_frag" | sed 's/^/     /'; exit 1
fi
echo "   OK"

echo "==> shared library closure of core binaries (recovery linker namespaces)"
python3 - "$WORK/out/unpack/root" <<'PY'
import os, subprocess, sys
root = sys.argv[1]
core = ["system/bin/init", "system/bin/recovery", "system/bin/twrp", "system/bin/adbd",
        "system/bin/sh", "system/bin/toybox", "system/bin/servicemanager", "system/bin/logd",
        "system/bin/keystore2",
        "vendor/bin/qseecomd", "vendor/bin/spdaemon", "vendor/bin/sec_nvm",
        "vendor/bin/hw/android.hardware.security.keymint-service-qti",
        "vendor/bin/hw/android.hardware.security.keymint-service-spu-qti",
        "vendor/bin/hw/android.hardware.gatekeeper-service-qti"]
def needed(p):
    out = subprocess.run(["readelf", "-dW", p], capture_output=True, text=True).stdout
    return [l.split("[")[1].split("]")[0] for l in out.splitlines() if "(NEEDED)" in l]
def interp(p):
    out = subprocess.run(["readelf", "-lW", p], capture_output=True, text=True).stdout
    for l in out.splitlines():
        if "interpreter:" in l: return l.split("interpreter:")[1].strip(" ]")
bad = []
for b in core:
    p = os.path.join(root, b)
    if not os.path.exists(p): bad.append(f"{b}: binary missing"); continue
    it = interp(p)
    if it and not os.path.exists(os.path.join(root, it.lstrip("/"))):
        bad.append(f"{b}: interpreter {it} missing")
    seen, todo = set(), [p]
    # ld.config.txt [recovery]: /system/bin only searches /system/lib64;
    # /vendor/bin falls back to the default paths (no /vendor/lib64/hw)
    libdirs = (["system/lib64"] if b.startswith("system/")
               else ["vendor/lib64", "system/lib64"])
    while todo:
        for l in needed(todo.pop()):
            if l in seen: continue
            seen.add(l)
            hit = next((os.path.join(root, d, l) for d in libdirs if os.path.exists(os.path.join(root, d, l))), None)
            if hit: todo.append(hit)
            else: bad.append(f"{b}: missing {l}")
for x in bad: print("   MISSING", x)
if bad: sys.exit("   ERROR: core binaries cannot link; do not flash this image")
print("   OK: all core binaries resolve")
PY
rm -rf "$WORK/out/unpack"

python3 - "$OUT" <<'PY' | tee -a "$WORK/out/$NAME.avbinfo.txt"
import struct, sys
h = open(sys.argv[1], 'rb').read(64)
ks, rs = struct.unpack('<II', h[8:16]); ver = struct.unpack('<I', h[40:44])[0]
print(f"   header: magic={h[:8].decode()} version={ver} kernel_size={ks} ramdisk_size={rs}")
assert h[:8] == b'ANDROID!' and ver == 4 and ks == 0, "unexpected boot header"
PY

echo "==> signature + hash verification (testkey)"
# avbtool looks up hash descriptors as <partition>.img next to the image
V=$WORK/out/verify
rm -rf "$V"; mkdir -p "$V"; cp "$OUT" "$V/recovery.img"
$AVBTOOL verify_image --image "$V/recovery.img" --key "$KEY"
rm -rf "$V"

if [ -z "$VBMETA" ]; then
    echo "==> chain check skipped (set VBMETA=<firmware>/vbmeta.img to verify against your firmware)"
    CHAIN_KEY=skip
else
    echo "==> chain check against $VBMETA"
    CHAIN_KEY=$($AVBTOOL info_image --image "$VBMETA" | grep -A4 'Partition Name:          recovery' | sed -n 's/.*Public key (sha1): *//p')
    CHAIN_LOC=$($AVBTOOL info_image --image "$VBMETA" | grep -A4 'Partition Name:          recovery' | sed -n 's/.*Rollback Index Location: *//p')
    echo "   vbmeta chains recovery at location $CHAIN_LOC to key $CHAIN_KEY"
fi
if [ "$CHAIN_KEY" = skip ]; then
    :
elif [ "$CHAIN_KEY" = "$KSHA" ]; then
    V=$WORK/out/verify; rm -rf "$V"; mkdir -p "$V"; cp "$OUT" "$V/recovery.img"
    $AVBTOOL verify_image --image "$V/recovery.img" \
        --expected_chain_partition "recovery:$CHAIN_LOC:$WORK/out/testkey_rsa4096.avbpubkey"
    rm -rf "$V"
    echo "   OK: recovery matches the vbmeta chain"
else
    echo "   WARNING: chain key differs ($CHAIN_KEY vs $KSHA); a locked device will reject this recovery"
fi

echo "==> publish to $WIN"
cp "$OUT" "$WIN/"
cp "$WORK/out/$NAME.avbinfo.txt" "$WIN/"
touch "$WIN/SHA256SUMS.txt"
(cd "$WIN" && sed -i "/  $NAME.img\$/d" SHA256SUMS.txt && sha256sum "$NAME.img" >> SHA256SUMS.txt)
echo "done: $WIN/$NAME.img"
