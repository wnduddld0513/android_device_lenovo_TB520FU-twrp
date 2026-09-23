# TWRP device tree for Lenovo Yoga Tab Plus (TB520FU)

TWRP 3.7.1 (twrp-14.1) for the Lenovo Yoga Tab Plus **TB520FU** ("Lapis",
Snapdragon 8 Gen 3 / SM8650 "pineapple"), built against ZUI 17.5.10.362
(Android 14). Landscape theme.

| | |
|---|---|
| SoC | SM8650 (pineapple), A/B, virtual A/B |
| Firmware base | ZUI 17.5.10.362 (Android 14, `UKQ1.240826.001`) |
| Kernel | none in recovery.img (boot header v4, the ABL uses the kernel from `boot`); `prebuilt/kernel` (stock GKI 6.1) is only used for the build's VINTF check |
| Panel | 2944×1840 dual-DSI, natively landscape |
| Touch | Novatek, module loaded from `vendor_boot` (`modules.load.recovery`) |
| Encryption | FBE v2 + metadata encryption (`wrappedkey_v0`), QTEE keymint V3 / gatekeeper |
| recovery partition | `recovery_a` / `recovery_b`, 104857600 bytes |
| AVB | signed with the AOSP `testkey_rsa4096`, rollback index 1 (see [Signing](#signing)) |

## Status

Almost everything works:
- `/data` decryption (FBE + metadata) and mount, internal storage
- ADB, MTP
- USB OTG
- display (DRM atomic, split planes over both DSI halves), touch, brightness
- battery / CPU temperature in the status bar
- etc.

Note: `eng` build; the `recovery`, `logd`, `kernel` and `hal_fastboot_default`
SELinux domains are permissive (`sepolicy/twrp_recovery.te`).

## Build

Any recent x86_64 Linux (Ubuntu 22.04 / 24.04 tested) with ~16 GB RAM and
~100 GB free disk.

### 1. Packages and repo

```bash
sudo apt install bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
    git git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev \
    liblz4-tool lz4 libncurses-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils \
    lzop pngcrush rsync schedtool squashfs-tools xsltproc zip unzip zlib1g-dev \
    python3 python-is-python3 openjdk-11-jdk-headless binutils file cpio \
    erofs-utils e2fsprogs android-sdk-libsparse-utils device-tree-compiler openssl
mkdir -p ~/bin && curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o ~/bin/repo && chmod +x ~/bin/repo
export PATH=~/bin:$PATH
```

Optional ccache. The Android 14 build sandbox makes everything outside
`out/` read-only, so keep the cache inside `out/`:

```bash
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=~/twrp/out/.ccache
```

### 2. Sources

```bash
mkdir -p ~/twrp && cd ~/twrp
repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-14.1 --git-lfs
repo sync -c -j8 --force-sync --no-clone-bundle --no-tags
git clone https://github.com/wnduddld0513/android_device_lenovo_TB520FU-twrp.git -b twrp-14.1 device/lenovo/TB520FU
```

### 3. Build

```bash
cd ~/twrp
bash device/lenovo/TB520FU/tools/build.sh
```

`tools/build.sh` does:
1. apply the source fixups in `patches/apply.sh`
2. clear the stale recovery ramdisk staging dir
3. run `lunch twrp_TB520FU-ap2a-eng` and `mka recoveryimage`

The same steps by hand:

```bash
bash device/lenovo/TB520FU/patches/apply.sh
rm -rf out/target/product/TB520FU/recovery
source build/envsetup.sh
lunch twrp_TB520FU-ap2a-eng
mka recoveryimage
```

### 4. Sign and check

```bash
bash device/lenovo/TB520FU/tools/sign.sh
# optional: also verify against your firmware's vbmeta
VBMETA=/path/to/firmware/vbmeta.img bash device/lenovo/TB520FU/tools/sign.sh
```

Output: `out/target/product/TB520FU/TWRP-3.7.1_14-TB520FU-<date>-landscape.img`
plus `SHA256SUMS.txt`. The script refuses to publish an image that would not
boot. It checks:
- the boot header (v4, no kernel) and the ramdisk contents
- the permissive domains and the `misc` label
- the VINTF fragments
- the shared-library closure of init, twrp, keystore2, qseecomd and keymint
- the AVB signature

## Source patches

twrp-14.1 does not build with `TW_INCLUDE_CRYPTO` on Android 14 as-is, and
this device needs a few runtime fixes. `patches/apply.sh` is idempotent. It
stops with an error if a patch no longer applies after a `repo sync`.

| # | What | Why |
|---|---|---|
| 1 | `-ndk_platform` → `-ndk` in bootable/recovery | Android 14 AIDL module names (= gerrit 8742) |
| 2 | `bootable_recovery-0001-…` | revert libtar dynamic fscrypt policy; its vold half never landed (gerrit 7723) |
| 3 | `bootable_recovery-0002-…` | drop legacy FDE calls removed from vold (gerrit 8744) |
| 4, 5 | libtar / recovery link deps | static libvold needs `libboot_control_client`, `libsysutils`, `libasync_safe` |
| 6 | `minuitwrp_graphics_drm.cpp` | 2944 px is wider than one SDE pipe; CLO atomic commit + split planes (from polygraphene's TB322FC tree) |
| 7 | `fscrypt_mount_metadata_encrypted()` args | fstab path was passed as `zoned_device`, so metadata decryption failed |
| 8 | fastboot HAL VINTF fragment → `framework` | a `device` fragment made servicemanager drop the framework manifest, so keystore2 never registered |
| 9 | Restore Defaults reloads the theme | otherwise the status bar and navbar break |
| 10 | NTFS mount updates the size | USB OTG showed 0 MB |
| 11 | unmounting removable storage clears its size | stale size after unmount |
| 12 | hot-unplug of fixed `/dev/block/sdX` removable entries | unmount, clear size, switch storage back to internal |

## Signing

Stock TB520FU firmware is signed with Lenovo's own AVB key. This recovery is
signed with the public AOSP `testkey_rsa4096` (sha1 `2597c218…`), using the
same footer layout as the stock recovery: `SHA256_RSA4096`, rollback index 1,
partition size 104857600, recovery fingerprint property.

- **Locked bootloader:** the installed `vbmeta` must chain `recovery`
  (rollback index location 1) to `testkey_rsa4096`, e.g. a testkey-resigned
  firmware. Otherwise the device will not boot this image.
- **Unlocked bootloader:** boots with any vbmeta (orange state).

## Installation

Back up your current `recovery_a` / `recovery_b` first.

- fastboot (unlocked):
  ```bash
  fastboot flash recovery_a TWRP-3.7.1_14-TB520FU-<date>-landscape.img
  fastboot flash recovery_b TWRP-3.7.1_14-TB520FU-<date>-landscape.img
  ```
- EDL: flash `recovery_a` / `recovery_b` (LUN 4) with your EDL tool of choice.

Boot it with `adb reboot recovery`.

## Updating the vendor blobs

`recovery/root/vendor` holds the QTEE / keymint / gatekeeper blobs, their init
rc and VINTF files, and the touch firmware, taken from ZUI 17.5.10.362. For
another firmware version, re-extract them from an unpacked QFIL/EDL package
(`rawprogram*.xml`, `super_*.img`, `vendor_boot.img`, `recovery.img`):

```bash
bash device/lenovo/TB520FU/tools/extract_blobs.sh /path/to/firmware
```

## Credits

- [TeamWin](https://github.com/TeamWin) and [minimal-manifest-twrp](https://github.com/minimal-manifest-twrp)
- [polygraphene](https://github.com/polygraphene): TB321FU / TB322FC device
  trees, which this tree is based on, and the minuitwrp DRM backend
- TWRP gerrit changes 7723, 8742, 8744
