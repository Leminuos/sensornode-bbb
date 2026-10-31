SUMMARY = "Out-of-tree driver for the Realtek RTL8188EU USB WiFi"
HOMEPAGE = "https://github.com/lwfinger/rtl8188eu"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=d7810fab7487fb0aad327b76f1be7cd7"

SRC_URI = "git://github.com/lwfinger/rtl8188eu.git;protocol=https;branch=v5.2.2.4"
SRCREV = "f42fc9c45d2086c415dce70d3018031b54a7beef"

PV = "5.2.2.4+git${SRCPV}"
S = "${WORKDIR}/git"

inherit module

EXTRA_OEMAKE += "ARCH=${ARCH} CROSS_COMPILE=${TARGET_PREFIX}"

do_install() {
    install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra
    install -m 0644 ${S}/8188eu.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/
}
