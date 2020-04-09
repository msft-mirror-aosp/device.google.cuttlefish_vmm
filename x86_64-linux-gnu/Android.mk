LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := 9p_device.policy
LOCAL_SRC_FILES := etc/seccomp/9p_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := balloon_device.policy
LOCAL_SRC_FILES := etc/seccomp/balloon_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := block_device.policy
LOCAL_SRC_FILES := etc/seccomp/block_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := common_device.policy
LOCAL_SRC_FILES := etc/seccomp/common_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := cras_audio_device.policy
LOCAL_SRC_FILES := etc/seccomp/cras_audio_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := fs_device.policy
LOCAL_SRC_FILES := etc/seccomp/fs_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := gpu_device.policy
LOCAL_SRC_FILES := etc/seccomp/gpu_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := input_device.policy
LOCAL_SRC_FILES := etc/seccomp/input_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := net_device.policy
LOCAL_SRC_FILES := etc/seccomp/net_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := null_audio_device.policy
LOCAL_SRC_FILES := etc/seccomp/null_audio_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := pmem_device.policy
LOCAL_SRC_FILES := etc/seccomp/pmem_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := rng_device.policy
LOCAL_SRC_FILES := etc/seccomp/rng_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := serial.policy
LOCAL_SRC_FILES := etc/seccomp/serial.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := tpm_device.policy
LOCAL_SRC_FILES := etc/seccomp/tpm_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := vfio_device.policy
LOCAL_SRC_FILES := etc/seccomp/vfio_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := vhost_net_device.policy
LOCAL_SRC_FILES := etc/seccomp/vhost_net_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := vhost_vsock_device.policy
LOCAL_SRC_FILES := etc/seccomp/vhost_vsock_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := wl_device.policy
LOCAL_SRC_FILES := etc/seccomp/wl_device.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := xhci.policy
LOCAL_SRC_FILES := etc/seccomp/xhci.policy
LOCAL_MODULE_PATH := $(HOST_OUT)/usr/share/cuttlefish/x86_64-linux-gnu/seccomp
LOCAL_MODULE_STEM := $(LOCAL_MODULE)
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_IS_HOST_MODULE := true
include $(BUILD_PREBUILT)
