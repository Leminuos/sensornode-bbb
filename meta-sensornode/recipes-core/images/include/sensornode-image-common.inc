python () {
    df = (d.getVar('DISTRO_FEATURES') or '').split()
    if 'sensornode-readonly' in df and 'sensornode-ota' not in df:
        bb.fatal("sensornode-readonly requires sensornode-ota")
    if 'sensornode-secureboot' in df and 'sensornode-ota' not in df:
        bb.fatal("sensornode-secureboot is only supported together with sensornode-ota")
    if 'sensornode-verity' in df and not all(f in df for f in ('sensornode-secureboot', 'sensornode-readonly')):
        bb.fatal("sensornode-verity requires sensornode-secureboot and sensornode-readonly")
}

inherit ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-verity', 'sensornode-verity', '', d)}

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
    'swupdate swupdate-www libubootenv-bin ota-confirm-boot sensornode-core-otad', '', d)}"

WKS_FILE = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-verity', 'bbb-sensornode-ab-verity.wks.in', \
    bb.utils.contains('DISTRO_FEATURES', 'sensornode-ota', 'bbb-sensornode-ab.wks.in', 'bbb-sensornode-single.wks.in', d), d)}"

# Với verity, ext4 + hash tree (~1/127 phần data) phải kết thúc trước FIT
IMAGE_ROOTFS_MAXSIZE = "${@int(d.getVar('SENSORNODE_VERITY_FIT_OFFSET_KiB')) * 127 // 128 \
    if bb.utils.contains('DISTRO_FEATURES', 'sensornode-verity', True, False, d) \
    else d.getVar('SENSORNODE_SLOT_SIZE_KiB')}"
IMAGE_OVERHEAD_FACTOR = "1.2"

python check_slot_usage() {
    slot_kib = int(d.getVar('IMAGE_ROOTFS_MAXSIZE'))
    warn_pct = int(d.getVar('SENSORNODE_SLOT_WARN_PERCENT'))
    used_kib = get_rootfs_size(d)
    used_pct = used_kib * 100 / slot_kib

    msg = "Slot usage: %.1f/%.1f MiB (%.1f%%)" % (used_kib / 1024, slot_kib / 1024, used_pct)
    if used_pct >= warn_pct:
        bb.warn("%s, over %d%% limit" % (msg, warn_pct))
    else:
        bb.plain(msg)
}
IMAGE_PREPROCESS_COMMAND:append = " check_slot_usage; "

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
    'read-only-rootfs overlayfs-etc', '', d)}"

OVERLAYFS_ETC_MOUNT_POINT = "/data"
OVERLAYFS_ETC_DEVICE = "LABEL=data"
OVERLAYFS_ETC_FSTYPE = "ext4"
OVERLAYFS_ETC_MOUNT_OPTIONS = "defaults,noatime"
OVERLAYFS_ETC_CREATE_MOUNT_DIRS = "0"

# ---------------------------------------------------------------------------
# sensornode-login
# ---------------------------------------------------------------------------
IMAGE_FEATURES:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-login', \
    'debug-tweaks ssh-server-openssh', '', d)}"

IMAGE_FEATURES:remove = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-login', '', \
    'debug-tweaks empty-root-password allow-empty-password allow-root-login \
     post-install-logging ssh-server-openssh ssh-server-dropbear', d)}"

# ---------------------------------------------------------------------------
# sensornode-devtools
# ---------------------------------------------------------------------------
IMAGE_INSTALL:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-devtools', \
    'i2c-tools evtest strace lsof mosquitto-clients inotify-tools \
     tslib tslib-calibrate tslib-tests systemd-analyze', '', d)}"
