SUMMARY = "SensorNode OTA update package"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PV = "${OTA_SW_VERSION}"

inherit swupdate

COMPATIBLE_MACHINE = "bbb-sensornode"

SRC_URI = "file://sw-description.in"

IMAGE_NAME = "${IMAGE_BASENAME}-${MACHINE}-${PV}"
IMAGE_LINK_NAME = "${IMAGE_BASENAME}-${MACHINE}"

IMAGE_DEPENDS = "${SENSORNODE_IMAGE}"
SWUPDATE_IMAGES = "${SENSORNODE_IMAGE}"

python () {
    if not bb.utils.contains('DISTRO_FEATURES', 'sensornode-ota', True, False, d):
        raise bb.parse.SkipRecipe("requires the sensornode-ota distro feature")
    d.setVarFlag('SWUPDATE_IMAGES_FSTYPES', d.getVar('SENSORNODE_IMAGE'), '.ext4.gz')
}

SWUPDATE_SIGNING = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'CMS', '', d)}"
SWUPDATE_CMS_KEY  = "${UBOOT_SIGN_KEYDIR}/${UBOOT_SIGN_KEYNAME}.key"
SWUPDATE_CMS_CERT = "${UBOOT_SIGN_KEYDIR}/${UBOOT_SIGN_KEYNAME}.crt"

do_render_swdesc() {
    sed -e "s|@VERSION@|${OTA_SW_VERSION}|g" \
        -e "s|@HW_REVISION@|${OTA_HW_REVISION}|g" \
        -e "s|@BOARD_NAME@|${OTA_BOARD_NAME}|g" \
        -e "s|@IMAGE_NAME@|${SENSORNODE_IMAGE}-${MACHINE}.ext4.gz|g" \
        -e "s|@SLOT_A_DEV@|${SENSORNODE_SLOT_A_DEV}|g" \
        -e "s|@SLOT_B_DEV@|${SENSORNODE_SLOT_B_DEV}|g" \
        ${WORKDIR}/sw-description.in > ${WORKDIR}/sw-description
}

addtask render_swdesc after do_unpack before do_swuimage
