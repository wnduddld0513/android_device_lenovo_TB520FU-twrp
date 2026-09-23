#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/lenovo/TB520FU

# Inherit from common AOSP config
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)

# Virtual A/B
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/launch_with_vendor_ramdisk.mk)

# Shipping API level (UKQ1 / Android 14)
PRODUCT_SHIPPING_API_LEVEL := 34

# Kernel: stock GKI 6.1.138-android14-11 from boot.img, only needed by the
# vintf check (recovery.img itself carries no kernel)
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilt/kernel:kernel
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false

# logd (libprocessgroup) aborts without /etc/task_profiles.json; TWRP only
# ships it as task_profiles/task_profiles_30.json (cf. TWRP gerrit 8739)
PRODUCT_COPY_FILES += \
    system/core/libprocessgroup/profiles/task_profiles.json:$(TARGET_COPY_OUT_RECOVERY)/root/system/etc/task_profiles.json

# Dynamic partitions
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# A/B
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS := \
    boot \
    dtbo \
    init_boot \
    odm \
    product \
    recovery \
    system \
    system_dlkm \
    system_ext \
    vbmeta \
    vbmeta_system \
    vendor \
    vendor_boot \
    vendor_dlkm

# fastbootd
PRODUCT_PACKAGES += \
    android.hardware.fastboot-service.example_recovery \
    fastbootd

# System-side dependencies of the vendor keymint/gatekeeper blobs
# (the vendor AIDL libs themselves are shipped in recovery/root/vendor/lib64)
TARGET_RECOVERY_DEVICE_MODULES += \
    libion \
    libdmabufheap \
    android.hardware.common-V2-ndk \
    android.system.keystore2-V4-ndk \
    android.security.aaid_aidl-cpp \
    android.hardware.security.keymint-V3-ndk \
    android.hardware.security.rkp-V3-ndk \
    android.hardware.confirmationui-V1-ndk \
    android.system.suspend-V1-ndk

# The recovery linker namespace only searches /system/lib64, so every library
# /system/bin/recovery and /system/bin/keystore2 need must be there (copies in
# /vendor/lib64 are invisible to them):
#  - keystore2-V4-ndk: android.security.maintenance-ndk
#  - aaid_aidl-cpp: libkeystore-attestation-application-id
#  - keymint-V3-ndk: recovery + keystore2; rkp-V3-ndk, confirmationui-V1-ndk: keystore2
#  - suspend-V1-ndk: libhardware_legacy (keymint-service-spu-qti, spdaemon)
RECOVERY_LIBRARY_SOURCE_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libion.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libdmabufheap.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.common-V2-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.system.keystore2-V4-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.security.aaid_aidl-cpp.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.security.keymint-V3-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.security.rkp-V3-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.hardware.confirmationui-V1-ndk.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/android.system.suspend-V1-ndk.so

# Enable Fuse Passthrough
PRODUCT_PROPERTY_OVERRIDES += persist.sys.fuse.passthrough.enable=true

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)
