FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-debug', '', ' file://no-tracing.cfg', d)}"
SRC_URI:append = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', ' file://dm-verity.cfg', '', d)}"

RRECOMMENDS:${KERNEL_PACKAGE_NAME}-base = ""
