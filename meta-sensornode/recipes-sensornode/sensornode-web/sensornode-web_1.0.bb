SUMMARY = "SensorNode web interface"
LICENSE = "CLOSED"

SRC_URI = "git://github.com/Leminuos/sensornode-web.git;protocol=https;branch=main"
SRCREV = "68c79ff1d0b39962310e473021882899f93ebf84"

PV = "1.0"
S = "${WORKDIR}/git"

inherit allarch

do_configure[noexec] = "1"
do_compile[noexec] = "1"

WEB_FILES = "index.html app.css tokens.css favicon.svg"

do_install() {
    install -d ${D}${datadir}/sensornode-web/js
    for f in ${WEB_FILES}; do
        install -m 0644 ${S}/$f ${D}${datadir}/sensornode-web/
    done
    install -m 0644 ${S}/js/*.js ${D}${datadir}/sensornode-web/js/
}

FILES:${PN} = "${datadir}/sensornode-web"
