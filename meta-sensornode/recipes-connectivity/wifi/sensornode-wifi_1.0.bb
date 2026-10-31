SUMMARY = "WiFi client for the RTL8188EU USB dongle"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://10-wlan0.link \
    file://20-wlan0.network \
    file://sensornode-wifi.service \
"

inherit systemd

SYSTEMD_SERVICE:${PN} = "sensornode-wifi.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${sysconfdir}/systemd/network
    install -m 0644 ${WORKDIR}/10-wlan0.link ${D}${sysconfdir}/systemd/network/
    install -m 0644 ${WORKDIR}/20-wlan0.network ${D}${sysconfdir}/systemd/network/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/sensornode-wifi.service ${D}${systemd_system_unitdir}/
}

RDEPENDS:${PN} = " \
    wpa-supplicant \
    wpa-supplicant-cli \
    wpa-supplicant-passphrase \
    wireless-regdb-static \
"
