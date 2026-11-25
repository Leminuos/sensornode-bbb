FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://10-sensornode-ntp.conf \
    file://10-sensornode-mdns.conf \
    file://10-sensornode.preset \
"

do_install:append() {
    install -D -m 0644 ${WORKDIR}/10-sensornode-mdns.conf \
        ${D}${systemd_unitdir}/resolved.conf.d/10-sensornode-mdns.conf
    install -D -m 0644 ${WORKDIR}/10-sensornode-ntp.conf \
        ${D}${systemd_unitdir}/timesyncd.conf.d/10-sensornode-ntp.conf
    sed -i 's#@NTP_SERVERS@#${SENSORNODE_NTP_SERVERS}#' \
        ${D}${systemd_unitdir}/timesyncd.conf.d/10-sensornode-ntp.conf
    install -D -m 0644 ${WORKDIR}/10-sensornode.preset \
        ${D}${systemd_unitdir}/system-preset/10-sensornode.preset
}

do_install[vardeps] += "SENSORNODE_NTP_SERVERS"

FILES:${PN} += " \
    ${systemd_unitdir}/timesyncd.conf.d/ ${systemd_unitdir}/resolved.conf.d/ \
    ${systemd_unitdir}/system-preset/10-sensornode.preset \
"
