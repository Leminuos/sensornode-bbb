FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://10-sensornode-ntp.conf"

do_install:append() {
    install -D -m 0644 ${WORKDIR}/10-sensornode-ntp.conf \
        ${D}${systemd_unitdir}/timesyncd.conf.d/10-sensornode-ntp.conf
}

FILES:${PN} += "${systemd_unitdir}/timesyncd.conf.d/"
