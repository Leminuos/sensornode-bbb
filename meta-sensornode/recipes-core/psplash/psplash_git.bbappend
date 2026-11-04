FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SPLASH_IMAGES = "file://psplash-sensornode.png;outsuffix=default"

SRC_URI += " \
    file://0001-sensornode-match-layout.patch \
    file://0002-psplash-fb-draw-before-turning-the-display-on.patch \
    file://psplash-bar.png \
    file://10-sensornode.conf \
"

EXTRA_OECONF += "--enable-img-fullscreen --disable-startup-msg"

do_configure:prepend() {
    install -m 0644 ${WORKDIR}/psplash-bar.png ${S}/base-images/psplash-bar.png
}

do_install:append() {
    install -d ${D}${systemd_system_unitdir}/psplash-start.service.d
    install -m 0644 ${WORKDIR}/10-sensornode.conf ${D}${systemd_system_unitdir}/psplash-start.service.d/
}

FILES:${PN} += "${systemd_system_unitdir}/psplash-start.service.d"
