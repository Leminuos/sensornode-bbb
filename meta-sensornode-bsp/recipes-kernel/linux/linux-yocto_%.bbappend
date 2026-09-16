FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://0001-bbb-sensornode-dts.patch"
SRC_URI += "file://bbb_sensornode.cfg"

KERNEL_CONFIG_FRAGMENTS:append = " ${WORKDIR}/bbb_sensornode.cfg"

COMPATIBLE_MACHINE:append = "|bbb-sensornode"
KMACHINE:bbb-sensornode = "beaglebone"
PREFERRED_PROVIDER_virtual/kernel ?= "linux-yocto"