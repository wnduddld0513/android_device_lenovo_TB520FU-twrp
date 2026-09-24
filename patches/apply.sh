#!/usr/bin/env bash
# Source fixups for the twrp-14.1 minimal manifest. Safe to re-run; re-run
# after every `repo sync`. tools/build.sh calls it automatically.
#
# usage: bash device/lenovo/TB520FU/patches/apply.sh [twrp-source-root]
#
# twrp-14.1 (TeamWin android-14.1 bootable/recovery + system/vold) does not
# build with TW_INCLUDE_CRYPTO on Android 14; 1-5 match the open TWRP gerrit
# changes 8742 / 8744 and the abandoned revert 7723. 6-12 are TB520FU runtime
# fixes (display, decryption, VINTF, GUI, removable storage).
set -euo pipefail
PATCHES=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOP=${1:-$(cd "$PATCHES/../../../.." && pwd)}
cd "$TOP"
[ -f build/envsetup.sh ] && [ -d bootable/recovery ] || { echo "ERROR: $TOP is not a TWRP source root" >&2; exit 1; }

apply_patch() { # repo-dir patch-file
    local dir=$1 patch=$2
    if git -C "$dir" apply --check "$patch" 2>/dev/null; then
        git -C "$dir" apply "$patch" && echo "applied $(basename "$patch")"
    elif git -C "$dir" apply --reverse --check "$patch" 2>/dev/null; then
        echo "already applied: $(basename "$patch")"
    else
        echo "ERROR: $(basename "$patch") does not apply to $dir" >&2; exit 1
    fi
}

# 1. bootable/recovery still links the Android 12 "-ndk_platform" AIDL module
#    names; Android 14 soong only generates "-ndk" (same fix as gerrit 8742).
files=$(grep -rl --include=Android.mk -e '-ndk_platform' bootable/recovery || true)
if [ -n "$files" ]; then
    echo "$files" | xargs sed -i -E 's/([A-Za-z0-9_.@-]+)-ndk_platform/\1-ndk/g'
    echo "patched ndk_platform -> ndk in:"; echo "$files" | sed 's/^/  /'
else
    echo "ndk_platform: nothing to patch"
fi

# 2. libtar uses the "dynamically choose fscrypt policy [1/2]" union API, but
#    the matching vold change [2/2] was never merged past 12.1. Gerrit 7723
#    reverts [1/2] back to the compile-time policy selection vold 14.1 has
#    (TW_USE_FSCRYPT_POLICY := 2 -> USE_FSCRYPT_POLICY_V2).
apply_patch bootable/recovery "$PATCHES/bootable_recovery-0001-revert-libtar-dynamic-fscrypt-policy.patch"

# 3. partition.cpp / partitionmanager.cpp still call legacy FDE functions
#    (cryptfs_check_passwd, cryptfs_get_password_type, ...) that vold removed
#    in 2021 ("Remove most of FDE support"). Gerrit 8744 drops those
#    codepaths; they are unreachable on FBE-only devices like TB520FU.
apply_patch bootable/recovery "$PATCHES/bootable_recovery-0002-remove-deprecated-FDE-codepaths.patch"

# 4. libtar links static libvold, whose Android 14 objects need
#    BootControlClient (Checkpoint.cpp), NetlinkEvent (libsysutils) and
#    async_safe_format_log. Add those to libtar's FBE link line.
MK=bootable/recovery/libtar/Android.mk
if ! grep -q 'libasync_safe' "$MK"; then
    sed -i 's/^\(\s*LOCAL_STATIC_LIBRARIES += libvold libscrypt_static\)$/\1 libasync_safe\n    LOCAL_SHARED_LIBRARIES += libboot_control_client libsysutils/' "$MK"
    grep -q 'libasync_safe' "$MK" && echo "patched libtar link deps" || { echo "ERROR: libtar link patch failed" >&2; exit 1; }
else
    echo "libtar link deps: already patched"
fi

# 5. The recovery binary also links static libvold (TW_INCLUDE_CRYPTO block)
#    and needs NetlinkEvent from libsysutils (already in the ramdisk via logd).
MK=bootable/recovery/Android.mk
if ! grep -q 'LOCAL_SHARED_LIBRARIES += libsysutils # vold' "$MK"; then
    sed -i 's/^\(\s*LOCAL_STATIC_LIBRARIES += libkeymint_support\)$/\1\n    LOCAL_SHARED_LIBRARIES += libsysutils # vold NetlinkEvent/' "$MK"
    grep -q 'libsysutils # vold' "$MK" && echo "patched recovery link deps" || { echo "ERROR: recovery link patch failed" >&2; exit 1; }
else
    echo "recovery link deps: already patched"
fi

# 6. minuitwrp DRM backend: the TB520FU panel is 2944 px wide (dual DSI), more
#    than one Qualcomm SDE pipe can scan out (~2560 px), so the stock legacy
#    drmModeSetCrtc/PageFlip backend shows garbage below the status bar.
#    Use polygraphene's backend (twrp-16.0-TB322FC @ edf59d8: CLO atomic
#    commit + layer topology split planes + SPR), which splits the frame over
#    as many planes as the connector's SDE topology has layer mixers.
DRM_SRC=$PATCHES/minuitwrp_graphics_drm.cpp
DRM_DST=bootable/recovery/minuitwrp/graphics_drm.cpp
if ! cmp -s "$DRM_SRC" "$DRM_DST"; then
    cp "$DRM_SRC" "$DRM_DST" && echo "replaced minuitwrp/graphics_drm.cpp (atomic/split-plane backend)"
else
    echo "minuitwrp graphics_drm.cpp: already replaced"
fi

# 7. partitionmanager.cpp passes the additional fstab path as the 6th argument
#    of vold's fscrypt_mount_metadata_encrypted(), which in 14.1 is
#    zoned_device (fstab_path is the 7th). A non-empty zoned_device makes vold
#    look for the metadata key in <dir>/default/key -> "No key found" and
#    metadata decryption fails. Pass "" as zoned_device.
PM=bootable/recovery/partitionmanager.cpp
OLD='Decrypt_Data->Current_File_System, TWFunc::Path_Exists(additional_fstab) ? additional_fstab : "")'
NEW='Decrypt_Data->Current_File_System, "" /* zoned_device */, TWFunc::Path_Exists(additional_fstab) ? additional_fstab : "")'
if grep -qF "$NEW" "$PM"; then
    echo "metadata decrypt zoned_device arg: already patched"
elif grep -qF "$OLD" "$PM"; then
    python3 - "$PM" "$OLD" "$NEW" <<'PY'
import sys
p, old, new = sys.argv[1:]
s = open(p).read()
open(p, "w").write(s.replace(old, new, 1))
PY
    grep -qF "$NEW" "$PM" && echo "patched metadata decrypt zoned_device arg" || { echo "ERROR: zoned_device patch failed" >&2; exit 1; }
else
    echo "ERROR: fscrypt_mount_metadata_encrypted call not found in $PM" >&2; exit 1
fi

# 8. The fastbootd HAL's VINTF fragment is type="device" but the recovery
#    build installs it into system/etc/vintf/manifest/. servicemanager then
#    rejects the whole framework manifest ("Cannot add a device manifest to
#    framework"), so keystore2 (declared in the same directory) can't
#    register and TWRP hangs on the splash waiting for it. Make it framework.
FB=hardware/interfaces/fastboot/aidl/default/android.hardware.fastboot-service.example.xml
if grep -q 'type="device"' "$FB"; then
    sed -i 's/type="device"/type="framework"/' "$FB" && echo "patched fastboot VINTF fragment -> framework"
else
    echo "fastboot VINTF fragment: already framework"
fi

# 9. Settings -> "Restore Defaults" calls DataManager::ResetDefaults(), which
#    clears every variable including the ones the theme XML defines (status
#    bar item positions, navbar). The status bar then collapses to x=0 and the
#    navbar disappears until TWRP restarts. Reload the theme afterwards.
ACT=bootable/recovery/gui/action.cpp
if grep -q 'RequestReload(); // re-apply theme variables' "$ACT"; then
    echo "restore defaults theme reload: already patched"
else
    python3 - "$ACT" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "\t\tDataManager::ResetDefaults();\n\t\tPartitionManager.Update_System_Details();\n\t\tPartitionManager.Mount_Current_Storage(true);\n"
new = old + "\t\tPageManager::RequestReload(); // re-apply theme variables\n"
if old not in s:
    sys.exit("ERROR: restoredefaultsettings body not found")
open(p, "w").write(s.replace(old, new, 1))
PY
    echo "patched restore defaults theme reload"
fi

# 10. TWPartition::Mount() returns right after a successful ntfs-3g mount,
#     skipping the "if (Removable) Update_Size()" at the end of the function.
#     NTFS USB OTG / microSD then show "(0MB)" in Select Storage until
#     something else refreshes all sizes (e.g. a backup). Update the size first.
PART=bootable/recovery/partition.cpp
if grep -q 'Update_Size(Display_Error); // ntfs-3g' "$PART"; then
    echo "ntfs-3g size update: already patched"
else
    python3 - "$PART" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "\t\tif (TWFunc::Exec_Cmd(cmd) == 0) {\n\t\t\treturn true;\n\t\t} else {\n\t\t\tLOGINFO(\"ntfs-3g failed to mount"
new = ("\t\tif (TWFunc::Exec_Cmd(cmd) == 0) {\n\t\t\tif (Removable)\n"
       "\t\t\t\tUpdate_Size(Display_Error); // ntfs-3g\n\t\t\treturn true;\n"
       "\t\t} else {\n\t\t\tLOGINFO(\"ntfs-3g failed to mount")
if s.count(old) != 1:
    sys.exit("ERROR: ntfs-3g mount branch not found exactly once")
open(p, "w").write(s.replace(old, new, 1))
PY
    echo "patched ntfs-3g size update"
fi

# 11. TWPartition::UnMount() never clears the cached sizes, so an unmounted /
#     unplugged USB OTG or microSD keeps showing its last "(xxxMB)" in Select
#     Storage. Zero them when a removable partition is unmounted; Mount()
#     refreshes them again (see 10).
if grep -q 'Backup_Size = 0; // unmounted removable' "$PART"; then
    echo "removable unmount size reset: already patched"
else
    python3 - "$PART" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = ("\t\t\treturn false;\n\t\t} else {\n\t\t\treturn true;\n\t\t}\n\t} else {\n\t\treturn true;\n\t}\n}\n\n"
       "bool TWPartition::ReMount(bool Display_Error) {")
new = ("\t\t\treturn false;\n\t\t} else {\n\t\t\tif (Removable)\n"
       "\t\t\t\tSize = Used = Free = Backup_Size = 0; // unmounted removable\n\t\t\treturn true;\n"
       "\t\t}\n\t} else {\n\t\treturn true;\n\t}\n}\n\n"
       "bool TWPartition::ReMount(bool Display_Error) {")
if s.count(old) != 1:
    sys.exit("ERROR: UnMount success branch not found exactly once")
open(p, "w").write(s.replace(old, new, 1))
PY
    echo "patched removable unmount size reset"
fi

# 12. Hot-unplug: Handle_Uevent() only acts on sysfs ("/devices/...") fstab
#     entries, so the fixed /dev/block/sdg1 (USB OTG) and mmcblk0p1 (microSD)
#     entries in twrp.flags ignore removal and keep a stale mount + size.
#     On a disk "remove" uevent, unmount (lazy if busy) every removable
#     partition on that disk, clear its sizes, move the current storage back
#     to the default one if needed and refresh the Mount page.
PM=bootable/recovery/partitionmanager.cpp
if grep -q '// removable hot-unplug' "$PM"; then
    echo "removable hot-unplug handling: already patched"
else
    python3 - "$PM" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = ("void TWPartitionManager::Handle_Uevent(const Uevent_Block_Data& uevent_data) {\n"
       "\tstd::vector<TWPartition*>::iterator iter;\n\n")
new = old + r'''	if (uevent_data.action == "remove" && !uevent_data.block_device.empty()) { // removable hot-unplug
		string disk = "/dev/block/" + uevent_data.block_device;
		for (iter = Partitions.begin(); iter != Partitions.end(); iter++) {
			TWPartition* part = *iter;
			if (!part->Removable || !part->Sysfs_Entry.empty() ||
			    part->Primary_Block_Device.compare(0, disk.size(), disk) != 0)
				continue;
			LOGINFO("%s: %s was unplugged\n", part->Mount_Point.c_str(), disk.c_str());
			if (part->Is_Mounted() && !part->UnMount(false)) {
				umount2(part->Mount_Point.c_str(), MNT_DETACH);
				LOGINFO("%s: lazy unmounted\n", part->Mount_Point.c_str());
			}
			part->Size = part->Used = part->Free = part->Backup_Size = 0;
			part->Is_Present = false;
			if (part->Is_Storage && DataManager::GetCurrentStoragePath() == part->Storage_Path) {
				TWPartition* def = Get_Default_Storage_Partition();
				if (def && def != part) {
					DataManager::SetValue("tw_storage_path", def->Storage_Path);
					DataManager::SetBackupFolder();
				}
			}
			if (PageManager::GetCurrentPage() == "mount")
				gui_changePage("mount"); // refresh the mount checkboxes
		}
	}

'''
if s.count(old) != 1:
    sys.exit("ERROR: Handle_Uevent start not found exactly once")
open(p, "w").write(s.replace(old, new, 1))
PY
    echo "patched removable hot-unplug handling"
fi

# 13. landscape theme, flash_done page: the A/B-only "Wipe Dalvik" button kept
#     the portrait placement (%indent%, %row21a_y%). row21a_y does not exist in
#     the landscape theme, so the button lands on top of the TWRP logo. Put it
#     where the non-A/B "Wipe Cache/Dalvik" button is (left of Reboot).
THEME=bootable/recovery/gui/theme/common/landscape.xml
if grep -q '<!-- TB520FU: A/B wipe dalvik -->' "$THEME"; then
    echo "landscape A/B wipe dalvik button: already patched"
else
    python3 - "$THEME" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = ('<condition var1="tw_ab_device" var2="1"/>\n\t\t\t\t<placement x="%indent%" y="%row21a_y%"/>\n'
       '\t\t\t\t<text>{@wipe_dalvik_btn=Wipe Dalvik}</text>')
new = ('<condition var1="tw_ab_device" var2="1"/>\n\t\t\t\t<!-- TB520FU: A/B wipe dalvik -->\n'
       '\t\t\t\t<placement x="%col2_x_left%" y="%row15a_y%"/>\n'
       '\t\t\t\t<text>{@wipe_dalvik_btn=Wipe Dalvik}</text>')
if s.count(old) != 1:
    sys.exit("ERROR: landscape A/B Wipe Dalvik placement not found exactly once")
open(p, "w").write(s.replace(old, new, 1))
PY
    echo "patched landscape A/B wipe dalvik button"
fi

# 14. Report any remaining references to removed FDE functions
left=$(grep -rn -E 'cryptfs_(check_footer|get_password_type|check_passwd)|delete_crypto_blk_dev|set_partition_data\(' \
    --include=*.cpp bootable/recovery | grep -v '^\s*//' || true)
[ -z "$left" ] && echo "FDE references: none left" || { echo "WARNING: FDE references remain:"; echo "$left"; }
