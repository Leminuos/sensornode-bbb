SUMMARY = "Save persistent journald on /data with rotation"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://10-persistent.conf \
    file://journald-data.conf \
    file://10-journal-on-data.conf \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = "systemd"

do_install() {
    install -d ${D}${sysconfdir}/systemd/journald.conf.d
    install -m 0644 ${WORKDIR}/10-persistent.conf \
        ${D}${sysconfdir}/systemd/journald.conf.d/10-persistent.conf

    install -d ${D}${sysconfdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/journald-data.conf \
        ${D}${sysconfdir}/tmpfiles.d/journald-data.conf

    install -d ${D}${systemd_system_unitdir}/systemd-journal-flush.service.d
    install -m 0644 ${WORKDIR}/10-journal-on-data.conf \
        ${D}${systemd_system_unitdir}/systemd-journal-flush.service.d/10-journal-on-data.conf
}

FILES:${PN} = " \
    ${sysconfdir}/systemd/journald.conf.d/10-persistent.conf \
    ${sysconfdir}/tmpfiles.d/journald-data.conf \
    ${systemd_system_unitdir}/systemd-journal-flush.service.d/10-journal-on-data.conf \
"
