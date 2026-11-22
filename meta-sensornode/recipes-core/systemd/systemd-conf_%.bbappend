FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://10-sensornode-ntp.conf file://50-sensornode-after-hmi.conf"

do_install:append() {
    install -D -m 0644 ${WORKDIR}/10-sensornode-ntp.conf \
        ${D}${systemd_unitdir}/timesyncd.conf.d/10-sensornode-ntp.conf
    sed -i 's#@NTP_SERVERS@#${SENSORNODE_NTP_SERVERS}#' \
        ${D}${systemd_unitdir}/timesyncd.conf.d/10-sensornode-ntp.conf

    for unit in systemd-networkd systemd-resolved systemd-timesyncd systemd-logind systemd-udev-trigger; do
        install -D -m 0644 ${WORKDIR}/50-sensornode-after-hmi.conf \
            ${D}${systemd_system_unitdir}/$unit.service.d/50-sensornode-after-hmi.conf
    done
}

do_install[vardeps] += "SENSORNODE_NTP_SERVERS"

FILES:${PN} += "${systemd_unitdir}/timesyncd.conf.d/ ${systemd_system_unitdir}/*.service.d/"
