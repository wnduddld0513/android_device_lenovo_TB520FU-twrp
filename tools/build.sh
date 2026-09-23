#!/usr/bin/env bash
# Build the TB520FU TWRP recovery image.
#   1. apply the source fixups (patches/apply.sh)
#   2. drop the recovery ramdisk staging dir: TWRP copies libraries from
#      system/lib64 into recovery/root only when that dir is (re)created, so an
#      incremental build otherwise ships stale copies (e.g. libminuitwrp.so)
#   3. lunch + mka recoveryimage
#
# usage: bash device/lenovo/TB520FU/tools/build.sh      (JOBS=<n> to override)
set -euo pipefail
TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOP=$(cd "$TREE/../../.." && pwd)
JOBS=${JOBS:-$(nproc)}

bash "$TREE/patches/apply.sh" "$TOP"

cd "$TOP"
PRODUCT_OUT=out/target/product/TB520FU
rm -rf "$PRODUCT_OUT/recovery" "$PRODUCT_OUT"/ramdisk-recovery.* "$PRODUCT_OUT/recovery.img"
mkdir -p out

# envsetup.sh / lunch / mka reference unset variables: keep nounset off
set +u
source build/envsetup.sh
lunch twrp_TB520FU-ap2a-eng
mka recoveryimage -j"$JOBS" 2>&1 | tee out/build_TB520FU.log
exit "${PIPESTATUS[0]}"
