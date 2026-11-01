SUMMARY = "SensorNode daemons: telemetryd and otad"
HOMEPAGE = "https://github.com/Leminuos/sensornode-core"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=490ed8a445d1812f676d85f19ba6a507"

SRC_URI = "git://github.com/Leminuos/sensornode-core.git;protocol=https;branch=master \
           file://sensornode-telemetryd.default \
           file://10-sensornode-bbb.conf \
           file://sensornode-telemetry-data.conf \
           file://sensornode-otad.default \
           file://sensornode-settingsd.default \
           file://sensornode-displayd.default \
           file://10-sensornode-settingsd-bbb.conf \
"

SRCREV = "e8c52ca1eb5354ab061f854c6aa5ba1186f5869f"

PV = "0.1.0+git${SRCPV}"
S = "${WORKDIR}/git"

inherit cmake pkgconfig systemd useradd

DEPENDS = "sqlite3 nlohmann-json mosquitto libubootenv swupdate"

EXTRA_OECMAKE += " \
    -DSENSORNODE_SYSTEMD_UNITDIR=${systemd_system_unitdir} \
    -DSENSORNODE_TMPFILESDIR=${nonarch_libdir}/tmpfiles.d \
    -DSENSORNODE_UDEVRULESDIR=${nonarch_base_libdir}/udev/rules.d \
"

USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "--system sensornode; --system i2c"
USERADD_PARAM:${PN} = "--system --gid sensornode --groups i2c \
                       --home-dir /nonexistent --no-create-home \
                       --shell /sbin/nologin sensornode"

PACKAGES =+ "${PN}-otad ${PN}-settingsd ${PN}-displayd"

SYSTEMD_PACKAGES = "${PN} ${PN}-otad ${PN}-settingsd ${PN}-displayd"
SYSTEMD_SERVICE:${PN} = "sensornode-telemetryd.service"
SYSTEMD_SERVICE:${PN}-otad = "sensornode-otad.service"
SYSTEMD_SERVICE:${PN}-settingsd = "sensornode-settingsd.service"
SYSTEMD_SERVICE:${PN}-displayd = "sensornode-displayd.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install:append() {
    install -m 0644 ${WORKDIR}/sensornode-telemetryd.default ${D}${sysconfdir}/default/sensornode-telemetryd
    install -m 0644 ${WORKDIR}/sensornode-otad.default ${D}${sysconfdir}/default/sensornode-otad
    install -m 0644 ${WORKDIR}/sensornode-settingsd.default ${D}${sysconfdir}/default/sensornode-settingsd
    install -m 0644 ${WORKDIR}/sensornode-displayd.default ${D}${sysconfdir}/default/sensornode-displayd

    install -d ${D}${systemd_system_unitdir}/sensornode-telemetryd.service.d
    install -m 0644 ${WORKDIR}/10-sensornode-bbb.conf ${D}${systemd_system_unitdir}/sensornode-telemetryd.service.d/

    install -d ${D}${systemd_system_unitdir}/sensornode-settingsd.service.d
    install -m 0644 ${WORKDIR}/10-sensornode-settingsd-bbb.conf ${D}${systemd_system_unitdir}/sensornode-settingsd.service.d/

    install -m 0644 ${WORKDIR}/sensornode-telemetry-data.conf ${D}${nonarch_libdir}/tmpfiles.d/
}

FILES:${PN}-otad = " \
    ${bindir}/sensornode-otad \
    ${systemd_system_unitdir}/sensornode-otad.service \
    ${sysconfdir}/default/sensornode-otad \
"

RDEPENDS:${PN}-otad = "${PN} swupdate"
CONFFILES:${PN}-otad = "${sysconfdir}/default/sensornode-otad"

FILES:${PN}-settingsd = " \
    ${bindir}/sensornode-settingsd \
    ${systemd_system_unitdir}/sensornode-settingsd.service \
    ${systemd_system_unitdir}/sensornode-settingsd.service.d \
    ${sysconfdir}/default/sensornode-settingsd \
"
RDEPENDS:${PN}-settingsd = "${PN}"
CONFFILES:${PN}-settingsd = "${sysconfdir}/default/sensornode-settingsd"

FILES:${PN}-displayd = " \
    ${bindir}/sensornode-displayd \
    ${systemd_system_unitdir}/sensornode-displayd.service \
    ${sysconfdir}/default/sensornode-displayd \
"
RDEPENDS:${PN}-displayd = "${PN} ${PN}-settingsd"
CONFFILES:${PN}-displayd = "${sysconfdir}/default/sensornode-displayd"

FILES:${PN} += " \
    ${systemd_system_unitdir}/sensornode-telemetryd.service.d \
    ${nonarch_libdir}/tmpfiles.d \
"
CONFFILES:${PN} = "${sysconfdir}/default/sensornode-telemetryd"
