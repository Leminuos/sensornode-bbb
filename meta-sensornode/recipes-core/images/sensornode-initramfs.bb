SUMMARY = "Initramfs that maps the dm-verity rootfs slot"
LICENSE = "MIT"

PACKAGE_INSTALL = "sensornode-initramfs-init"

IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
IMAGE_FSTYPES = "cpio.gz"
IMAGE_NAME_SUFFIX ?= ""

# Chỉ lấy dependency bắt buộc: không cần ldconfig, udhcpc trong initramfs
NO_RECOMMENDATIONS = "1"

inherit core-image

IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
