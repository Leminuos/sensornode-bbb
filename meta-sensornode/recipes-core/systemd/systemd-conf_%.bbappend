FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://10-sensornode-ntp.conf"

do_install:append() {
    install -D -m 0644 ${WORKDIR}/10-sensornode-ntp.conf \
        ${D}${systemd_unitdir}/timesyncd.conf.d/10-sensornode-ntp.conf
    sed -i 's#@NTP_SERVERS@#${SENSORNODE_NTP_SERVERS}#' \
        ${D}${systemd_unitdir}/timesyncd.conf.d/10-sensornode-ntp.conf
}

do_install[vardeps] += "SENSORNODE_NTP_SERVERS"

FILES:${PN} += "${systemd_unitdir}/timesyncd.conf.d/"
