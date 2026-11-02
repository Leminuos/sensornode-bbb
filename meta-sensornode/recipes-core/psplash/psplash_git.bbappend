FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SPLASH_IMAGES = "file://psplash-sensornode.png;outsuffix=default"

SRC_URI += " \
    file://0001-sensornode-match-S0b-layout.patch \
    file://psplash-bar.png \
"

EXTRA_OECONF += "--enable-img-fullscreen --disable-startup-msg"

do_configure:prepend() {
    install -m 0644 ${WORKDIR}/psplash-bar.png ${S}/base-images/psplash-bar.png
}
