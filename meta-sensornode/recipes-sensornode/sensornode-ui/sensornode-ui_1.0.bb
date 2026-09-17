SUMMARY = "SensorNode Qt touchscreen HMI"
HOMEPAGE = "https://github.com/Leminuos/sensornode-ui"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3da9cfbcb788c80a0384361b4de20420"

SRC_URI = "git://github.com/Leminuos/sensornode-ui.git;protocol=https;branch=master \
           file://sensornode-ui.service"
SRCREV = "8a129268dad2e70edb3c036010adac7a4d46aab5"

PV = "1.0+git${SRCPV}"
S = "${WORKDIR}/git"

inherit cmake_qt5 systemd

DEPENDS += "qtbase qtcharts mosquitto"

RDEPENDS:${PN} = "qtbase-plugins tslib-conf ttf-dejavu-sans"

EXTRA_OECMAKE += "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-debug', '-DPRODUCTION_BUILD=OFF', '-DPRODUCTION_BUILD=ON', d)}"

SYSTEMD_SERVICE:${PN} = "sensornode-ui.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/sensornode-ui ${D}${bindir}/sensornode-ui

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/sensornode-ui.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += "${bindir}/sensornode-ui"
FILES:${PN} += "${systemd_system_unitdir}/sensornode-ui.service"
