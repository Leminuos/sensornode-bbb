FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://10-sensornode-ntp.conf \
    file://10-sensornode-mdns.conf \
    file://10-sensornode.preset \
    file://20-sensornode-after-ui.conf \
    file://20-sensornode-udev-trigger.conf \
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

    for unit in ${SENSORNODE_AFTER_UI_UNITS}; do
        install -D -m 0644 ${WORKDIR}/20-sensornode-after-ui.conf \
            ${D}${systemd_system_unitdir}/$unit.d/20-sensornode-after-ui.conf
    done

    install -D -m 0644 ${WORKDIR}/20-sensornode-udev-trigger.conf \
        ${D}${systemd_system_unitdir}/systemd-udev-trigger.service.d/20-sensornode-udev-trigger.conf
}

SENSORNODE_AFTER_UI_UNITS = "systemd-logind.service systemd-timesyncd.service systemd-resolved.service \
    serial-getty@ttyS0.service sshdgenkeys.service"

do_install[vardeps] += "SENSORNODE_NTP_SERVERS"

FILES:${PN} += " \
    ${systemd_unitdir}/timesyncd.conf.d/ ${systemd_unitdir}/resolved.conf.d/ \
    ${systemd_unitdir}/system-preset/10-sensornode.preset \
    ${@' '.join('${systemd_system_unitdir}/%s.d' % u for u in d.getVar('SENSORNODE_AFTER_UI_UNITS').split())} \
    ${systemd_system_unitdir}/systemd-udev-trigger.service.d \
"
