FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:bbb-sensornode = " file://fw_env.config"

do_install:append:bbb-sensornode() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/fw_env.config ${D}${sysconfdir}/fw_env.config
}

FILES:${PN}:append:bbb-sensornode = " ${sysconfdir}/fw_env.config"
