python () {
    df = (d.getVar('DISTRO_FEATURES') or '').split()
    if 'sensornode-readonly' in df and 'sensornode-ota' not in df:
        bb.fatal("sensornode-readonly requires sensornode-ota")
    if 'sensornode-secureboot' in df and 'sensornode-ota' not in df:
        bb.fatal("sensornode-secureboot is only supported together with sensornode-ota")
    if 'sensornode-debug' in df and 'sensornode-readonly' in df:
        bb.warn("sensornode-debug + sensornode-readonly is an untested combination")
}

IMAGE_FSTYPES = " wic wic.bmap ext4.gz"

# ---------------------------------------------------------------------------
# Persistent /data partition
# ---------------------------------------------------------------------------
IMAGE_INSTALL:append = " sensornode-data-mount journald-persistent"
do_image_wic[depends] += "virtual/bootloader:do_deploy sensornode-data-image:do_deploy"

create_data_mountpoint() {
    install -d -m 0755 ${IMAGE_ROOTFS}/data
}
ROOTFS_POSTPROCESS_COMMAND += "create_data_mountpoint; "

# ---------------------------------------------------------------------------
# sensornode-ota
# ---------------------------------------------------------------------------
IMAGE_INSTALL:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-ota', \
    'swupdate swupdate-www libubootenv-bin ota-confirm-boot', '', d)}"

WKS_FILE = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-ota', \
    'bbb-sensornode-ab.wks.in', 'bbb-sensornode-single.wks.in', d)}"

IMAGE_ROOTFS_MAXSIZE = "${SENSORNODE_SLOT_SIZE_KiB}"

write_ota_metadata() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}
    echo "${OTA_BOARD_NAME} ${OTA_HW_REVISION}" > ${IMAGE_ROOTFS}${sysconfdir}/hwrevision
    echo "${OTA_SW_VERSION}"                    > ${IMAGE_ROOTFS}${sysconfdir}/sw-versions
}
ROOTFS_POSTPROCESS_COMMAND += "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-ota', 'write_ota_metadata; ', '', d)}"

# ---------------------------------------------------------------------------
# sensornode-readonly
# ---------------------------------------------------------------------------
IMAGE_FEATURES:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-readonly', \
    'read-only-rootfs', '', d)}"

# ---------------------------------------------------------------------------
# sensornode-debug
# ---------------------------------------------------------------------------
IMAGE_FEATURES:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-debug', \
    'debug-tweaks ssh-server-openssh', '', d)}"

IMAGE_INSTALL:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-debug', \
    'i2c-tools evtest strace lsof mosquitto-clients inotify-tools \
     tslib tslib-calibrate tslib-tests systemd-analyze', '', d)}"

IMAGE_FEATURES:remove = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-debug', '', \
    'debug-tweaks empty-root-password allow-empty-password allow-root-login \
     post-install-logging ssh-server-openssh ssh-server-dropbear', d)}"
