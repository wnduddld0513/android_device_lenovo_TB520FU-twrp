#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Lenovo Yoga Tab Plus (TB520FU, "Lapis") - SM8650 (pineapple)
# Based on the stock ZUI_17.5.10.362_260719_ROW firmware.
#

DEVICE_PATH := device/lenovo/TB520FU

# For building with minimal manifest
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a-dotprod
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a76

TARGET_SUPPORTS_64_BIT_APPS := true
TARGET_IS_64_BIT := true

ENABLE_CPUSETS := true
ENABLE_SCHEDBOOST := true

# Bootloader
BOARD_VENDOR := lenovo
TARGET_SOC := pineapple
TARGET_BOOTLOADER_BOARD_NAME := pineapple
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true
TARGET_USES_UEFI := true

# Platform
BOARD_USES_QCOM_HARDWARE := true
TARGET_BOARD_PLATFORM := pineapple
TARGET_BOARD_PLATFORM_GPU := qcom-adreno750
QCOM_BOARD_PLATFORMS += pineapple

# Kernel
# Stock recovery.img is header v4 without a kernel; ABL takes the kernel
# from boot.img and the vendor ramdisk from vendor_boot.img.
BOARD_BOOT_HEADER_VERSION := 4
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_RAMDISK_USE_LZ4 := true
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true
# Harmless extra: ask init for permissive SELinux. Whether the ABL forwards the
# recovery header cmdline is unknown (both the UefiLog "Cmdline:" line and the
# dmesg "Kernel command line" are truncated); sepolicy/ covers it regardless.
BOARD_KERNEL_CMDLINE := androidboot.selinux=permissive
# The stock GKI kernel is copied to $(PRODUCT_OUT)/kernel by device.mk only for
# the vintf check. TARGET_PREBUILT_KERNEL is not used: combined with
# TW_LOAD_VENDOR_MODULES it trips a make syntax bug in vendor/twrp/build/tasks/kernel.mk.

# Partitions (sizes from stock rawprogram*.xml and super LP metadata)
BOARD_FLASH_BLOCK_SIZE := 262144
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_DTBOIMG_PARTITION_SIZE := 25165824
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 104857600
BOARD_HAS_LARGE_FILESYSTEM := true

BOARD_SUPER_PARTITION_SIZE := 23622320128
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 23618125824
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    odm \
    product \
    system \
    system_dlkm \
    system_ext \
    vendor \
    vendor_dlkm

BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_ODM := odm
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm

TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# System as root
BOARD_ROOT_EXTRA_FOLDERS := \
    bt_firmware \
    dsp \
    firmware \
    metadata \
    odm_dlkm \
    persist \
    spunvm \
    system_dlkm \
    vendor_dlkm
BOARD_SUPPRESS_SECURE_ERASE := true

# Recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
BOARD_HAS_NO_SELECT_BUTTON := true
BOARD_USES_RECOVERY_AS_BOOT :=
BOARD_USES_GENERIC_KERNEL_IMAGE := true
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT :=
RECOVERY_SDCARD_ON_DATA := true

# SELinux: the locked bootloader keeps init enforcing; make the recovery
# domain permissive (eng build) so TWRP and its vendor services can run
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy

# Properties
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# Verified Boot
# Signed with the AOSP testkey_rsa4096 (pubkey sha1 2597c218...), the key the
# 096 ABL of the resigned ROM trusts. Note: stock vbmeta chains "recovery"
# (rollback location 1) to Lenovo's own key (sha1 8fcb864f...), which is not
# available. Stock recovery rollback index is 1.
BOARD_AVB_ENABLE := true
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA4096
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 1
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 1

# Crypto
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)
BOOT_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
BOARD_USES_METADATA_PARTITION := true
# AIDL keymint/gatekeeper services are started by init.recovery.qcom.rc
# (twrp-common's HIDL qcom_decrypt rc files are not used)
TW_USE_FSCRYPT_POLICY := 2

# Display: TB520FU panel (nt36532 tianma/boe 3K, dual DSI 2x1472x1840)
# is natively landscape 2944x1840, so the framebuffer needs no rotation.
# The Novatek touch controller reports portrait coordinates, so swap X/Y and
# flip Y (values from nfe613920-cmyk/android_device_lenovo_TB520FU commit
# 29b871c "Fix default orientation and inverted touch"; verify on device).
TW_THEME := landscape_hdpi
TW_ROTATION := 0
RECOVERY_TOUCHSCREEN_SWAP_XY := true
RECOVERY_TOUCHSCREEN_FLIP_X := false
RECOVERY_TOUCHSCREEN_FLIP_Y := true
TW_FRAMERATE := 60
TW_BRIGHTNESS_PATH := "/sys/class/backlight/panel0-backlight/brightness"
TW_MAX_BRIGHTNESS := 2047
TW_DEFAULT_BRIGHTNESS := 800
TW_SCREEN_BLANK_ON_BOOT := true
TW_INPUT_BLACKLIST := "hbtp_vm"

# Kernel modules
# Loaded from vendor_dlkm / vendor ramdisk after first stage init.
# Touch module name(s) are filled in from vendor_dlkm by scripts/extract_blobs.sh.
TW_LOAD_VENDOR_MODULES := "qcom_pil_info.ko qmi_helpers.ko qcom_smd.ko qcom_glink.ko qcom_glink_smem.ko rproc_qcom_common.ko qcom_sysmon.ko qcom_q6v5.ko qcom_ramdump.ko qcom_q6v5_pas.ko snd_event_dlkm.ko pdr_interface.ko q6_pdr_dlkm.ko q6_notifier_dlkm.ko gpr_dlkm.ko spf_core_dlkm.ko adsp_loader_dlkm.ko"
TW_LOAD_VENDOR_MODULES_EXCLUDE_GKI := true

# TWRP specific build flags
TW_DEVICE_VERSION ?= TB520FU
TW_EXCLUDE_APEX := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_EXTRA_LANGUAGES := true
TW_DEFAULT_LANGUAGE := en
TW_HAS_EDL_MODE := true
TW_INCLUDE_FASTBOOTD := true
TW_INCLUDE_LIBRESETPROP := true
TW_INCLUDE_LPDUMP := true
TW_INCLUDE_LPTOOLS := true
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_RESETPROP := true
TW_NO_BIND_SYSTEM := true
TW_NO_LEGACY_PROPS := true
TW_NO_HAPTICS := true
TW_USE_MODEL_HARDWARE_ID_FOR_DEVICE_ID := true
TW_USE_TOOLBOX := true
TW_BACKUP_EXCLUSIONS := /data/fonts
TARGET_USES_MKE2FS := true
TARGET_RECOVERY_QCOM_RTC_FIX := true
# thermal_zone numbers change between boots; cpu_temp_link.sh links cpuss-0 here
TW_CUSTOM_CPU_TEMP_PATH := /tmp/cpu_temp

# Debug
TWRP_EVENT_LOGGING := true
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true

# Statusbar icons
TW_STATUS_ICONS_ALIGN := center
