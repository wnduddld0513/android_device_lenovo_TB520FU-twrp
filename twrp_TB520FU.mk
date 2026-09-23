#
# Copyright (C) 2026 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit some common TWRP stuff.
$(call inherit-product, vendor/twrp/config/common.mk)

# Inherit from TB520FU device
$(call inherit-product, device/lenovo/TB520FU/device.mk)

PRODUCT_DEVICE := TB520FU
PRODUCT_NAME := twrp_TB520FU
PRODUCT_BRAND := Lenovo
PRODUCT_MODEL := Lenovo TB520FU
PRODUCT_MANUFACTURER := lenovo

PRODUCT_GMS_CLIENTID_BASE := android-lenovo
