FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'file://verified-boot.cfg', '', d)} \
"
