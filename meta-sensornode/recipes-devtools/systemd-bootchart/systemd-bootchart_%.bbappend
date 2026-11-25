FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://10-sensornode-bootchart.conf"

# Chỉ bật khi cần đo boot
SYSTEMD_AUTO_ENABLE = "disable"

do_install:append() {
    install -D -m 0644 ${WORKDIR}/10-sensornode-bootchart.conf \
        ${D}${systemd_system_unitdir}/systemd-bootchart.service.d/10-sensornode-bootchart.conf
    sed -i 's#@BOOTCHART@#${systemd_unitdir}/systemd-bootchart#' \
        ${D}${systemd_system_unitdir}/systemd-bootchart.service.d/10-sensornode-bootchart.conf
}

FILES:${PN} += "${systemd_system_unitdir}/systemd-bootchart.service.d"
