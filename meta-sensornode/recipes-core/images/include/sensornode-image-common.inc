python () {
    df = (d.getVar('DISTRO_FEATURES') or '').split()
    if 'sensornode-readonly' in df and 'sensornode-ota' not in df:
        bb.fatal("sensornode-readonly requires sensornode-ota")
    if 'sensornode-secureboot' in df and 'sensornode-ota' not in df:
        bb.fatal("sensornode-secureboot is only supported together with sensornode-ota")
    if 'sensornode-secureboot' in df and 'sensornode-readonly' not in df:
        bb.fatal("sensornode-secureboot requires sensornode-readonly")
}

IMAGE_FSTYPES = " wic wic.bmap ${SENSORNODE_SLOT_FSTYPE}.gz bootfs.gz"
IMAGE_TYPEDEP:wic += "bootfs ${SENSORNODE_SLOT_FSTYPE}"

# ---------------------------------------------------------------------------
# Persistent /data partition
# ---------------------------------------------------------------------------
IMAGE_INSTALL:append = " sensornode-data-mount journald-persistent"
do_image_wic[depends] += "virtual/bootloader:do_deploy sensornode-data-image:do_deploy"

create_data_mountpoint() {
    install -d -m 0755 ${IMAGE_ROOTFS}/data
}
ROOTFS_POSTPROCESS_COMMAND += "create_data_mountpoint; "

SENSORNODE_MASKED_UNITS = "systemd-network-generator.service \
    ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-debug', '', 'sys-kernel-debug.mount', d)}"

mask_unused_units() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}/systemd/system
    for unit in ${SENSORNODE_MASKED_UNITS}; do
        ln -sf /dev/null ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/$unit
    done
}
ROOTFS_POSTPROCESS_COMMAND += "mask_unused_units; "

# Không có /etc/init.d, rc.local hay phân vùng GPT, còn kernel cmdline do U-Boot đặt cố định nên
# các tham số systemd.* trên cmdline cũng không dùng tới. Chỉ giữ fstab và getty generator.
SENSORNODE_MASKED_GENERATORS = "systemd-debug-generator systemd-gpt-auto-generator \
    systemd-rc-local-generator systemd-run-generator systemd-system-update-generator \
    systemd-sysv-generator"

mask_unused_generators() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}/systemd/system-generators
    for gen in ${SENSORNODE_MASKED_GENERATORS}; do
        ln -sf /dev/null ${IMAGE_ROOTFS}${sysconfdir}/systemd/system-generators/$gen
    done
}
ROOTFS_POSTPROCESS_COMMAND += "mask_unused_generators; "

# hwdb chỉ bổ sung tên hãng, sơ đồ phím, thông số chuột/touchpad. Touchscreen đi qua tslib đọc thẳng evdev.
BAD_RECOMMENDATIONS += "udev-hwdb"

# Kernel đặt giờ từ DS3231 trước khi systemd chạy, còn mốc giờ timesyncd lưu nằm trên tmpfs.
# Vì vậy timesyncd chỉ còn việc đồng bộ NTP, chạy như service thường để không chặn sysinit.target.
move_timesyncd_off_sysinit() {
    unit=${IMAGE_ROOTFS}${systemd_system_unitdir}/systemd-timesyncd.service
    [ -f $unit ] || return 0

    sed -i -e '/^DefaultDependencies=no$/d' \
           -e '/^Before=time-set.target sysinit.target shutdown.target$/d' \
           -e '/^Wants=time-set.target$/d' \
           -e 's/^WantedBy=sysinit.target$/WantedBy=multi-user.target/' $unit
    if grep -qE '^(DefaultDependencies=no|Before=.*sysinit|WantedBy=sysinit)' $unit; then
        bbfatal "systemd-timesyncd.service changed upstream, update the sed patterns"
    fi

    wants=${IMAGE_ROOTFS}${sysconfdir}/systemd/system
    if [ -L $wants/sysinit.target.wants/systemd-timesyncd.service ]; then
        rm -f $wants/sysinit.target.wants/systemd-timesyncd.service
        install -d $wants/multi-user.target.wants
        ln -sf ${systemd_system_unitdir}/systemd-timesyncd.service $wants/multi-user.target.wants/
    fi
}
ROOTFS_POSTPROCESS_COMMAND += "move_timesyncd_off_sysinit; "

# ---------------------------------------------------------------------------
# sensornode-ota
# ---------------------------------------------------------------------------
IMAGE_INSTALL:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-ota', \
    'swupdate swupdate-www libubootenv-bin ota-confirm-boot sensornode-core-otad', '', d)}"

WKS_FILE = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-ota', \
    'bbb-sensornode-ab.wks.in', 'bbb-sensornode-single.wks.in', d)}"

IMAGE_ROOTFS_MAXSIZE = "${SENSORNODE_SLOT_SIZE_KiB}"
IMAGE_OVERHEAD_FACTOR = "1.2"

inherit sensornode-bootfs ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'sensornode-verity', '', d)}

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
     tslib tslib-calibrate tslib-tests systemd-analyze systemd-bootchart', '', d)}"
