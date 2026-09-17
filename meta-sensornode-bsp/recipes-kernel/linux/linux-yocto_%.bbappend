FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://0001-bbb-sensornode-dts.patch \
    file://bbb_sensornode.cfg \
"

COMPATIBLE_MACHINE:append = "|bbb-sensornode"
KMACHINE:bbb-sensornode = "beaglebone"
