SUMMARY = "WiFi client for the RTL8188EU USB dongle"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://10-wlan0.link \
    file://20-wlan0.network \
    file://sensornode-wifi.service \
    file://sensornode-wifi-ctrl.conf \
    file://sensornode-wifi-data.conf \
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

    install -d ${D}${sysconfdir}/wpa_supplicant
    install -m 0644 ${WORKDIR}/sensornode-wifi-ctrl.conf ${D}${sysconfdir}/wpa_supplicant/sensornode-ctrl.conf

    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/sensornode-wifi-data.conf ${D}${nonarch_libdir}/tmpfiles.d/
}

FILES:${PN} += "${nonarch_libdir}/tmpfiles.d"

# Group sensornode của control socket do sensornode-core tạo.
RDEPENDS:${PN} = " \
    sensornode-core \
    wpa-supplicant \
    wpa-supplicant-cli \
    wpa-supplicant-passphrase \
    wireless-regdb-static \
"
