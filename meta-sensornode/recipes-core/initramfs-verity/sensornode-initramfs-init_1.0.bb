SUMMARY = "Initramfs init that maps the rootfs slot with dm-verity"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://init"

S = "${WORKDIR}"

inherit allarch

do_install() {
    install -m 0755 ${WORKDIR}/init ${D}/init
    install -d ${D}/dev ${D}/proc ${D}/sys ${D}/newroot
}

FILES:${PN} = "/init /dev /proc /sys /newroot"
RDEPENDS:${PN} = "busybox libdevmapper"
