SUMMARY = "SensorNode OTA update package"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PV = "${OTA_SW_VERSION}"

inherit swupdate

COMPATIBLE_MACHINE = "bbb-sensornode"

SRC_URI = "file://sw-description"

IMAGE_NAME = "${IMAGE_BASENAME}-${MACHINE}-${PV}"
IMAGE_LINK_NAME = "${IMAGE_BASENAME}-${MACHINE}"

IMAGE_DEPENDS = "${SENSORNODE_IMAGE}"
SWUPDATE_IMAGES = "${SENSORNODE_IMAGE}"

python () {
    if not bb.utils.contains('DISTRO_FEATURES', 'sensornode-ota', True, False, d):
        raise bb.parse.SkipRecipe("requires the sensornode-ota distro feature")
    d.setVarFlag('SWUPDATE_IMAGES_FSTYPES', d.getVar('SENSORNODE_IMAGE'), '.' + d.getVar('SENSORNODE_SLOT_FSTYPE') + '.gz')
}

SWUPDATE_SIGNING = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'CMS', '', d)}"
SWUPDATE_CMS_KEY  = "${UBOOT_SIGN_KEYDIR}/${UBOOT_SIGN_KEYNAME}.key"
SWUPDATE_CMS_CERT = "${UBOOT_SIGN_KEYDIR}/${UBOOT_SIGN_KEYNAME}.crt"

do_swuimage[vardeps] += "${@swupdate_find_bitbake_variables(d)}"
