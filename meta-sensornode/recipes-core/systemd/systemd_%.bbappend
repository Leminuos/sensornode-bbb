# backlight, randomseed: lưu trạng thái vào /var/lib là tmpfs nên không giữ được qua boot.
# Độ sáng do UI đặt theo settingsd.
# userdb, utmp: không có unit dùng DynamicUser, không cần who/last.
# Phần còn lại chỉ tốn dung lượng rootfs, thiết bị không dùng.
PACKAGECONFIG:remove = " \
    backlight \
    randomseed \
    userdb \
    utmp \
    binfmt \
    hibernate \
    ima \
    localed \
    machined \
    nss-mymachines \
    quotacheck \
    vconsole \
"

# Không dùng POSIX message queue, FUSE hay configfs
# Bỏ mount để không phải chạy modprobe@ lúc boot.
SENSORNODE_UNUSED_MOUNTS = "dev-mqueue.mount sys-fs-fuse-connections.mount sys-kernel-config.mount"

do_install:append() {
    for unit in ${SENSORNODE_UNUSED_MOUNTS}; do
        rm -f ${D}${systemd_system_unitdir}/$unit ${D}${systemd_system_unitdir}/sysinit.target.wants/$unit
    done
}
