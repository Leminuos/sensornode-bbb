SUMMARY = "Pre-populated ext4 image for the /data partition"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

S = "${WORKDIR}"

DEPENDS = "e2fsprogs-native"

inherit deploy nopackages

do_compile[cleandirs] = "${WORKDIR}/data-root"

do_compile() {
    install -d ${WORKDIR}/data-root/journal

    install -d ${WORKDIR}/data-root/config

    mke2fs -t ext4 -L data \
           -d ${WORKDIR}/data-root \
           ${WORKDIR}/${SENSORNODE_DATA_IMG} \
           ${SENSORNODE_DATA_SIZE_KiB}
}

do_deploy() {
    install -Dm 0644 ${WORKDIR}/${SENSORNODE_DATA_IMG} ${DEPLOYDIR}/${SENSORNODE_DATA_IMG}
}

addtask deploy after do_compile before do_build
