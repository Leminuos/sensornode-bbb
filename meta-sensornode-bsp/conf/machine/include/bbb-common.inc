require conf/machine/beaglebone-yocto.conf

MACHINEOVERRIDES =. "beaglebone-yocto:"

KERNEL_DEVICETREE       = "am335x-boneblack.dtb"

UBOOT_DTB_BINARY        = "u-boot.dtb"
UBOOT_NODTB_BINARY      = "u-boot-nodtb.bin"

UBOOT_ENTRYPOINT        = "0x80008000"
UBOOT_LOADADDRESS       = "0x80008000"
UBOOT_DTB_LOADADDRESS   = "0x88000000"

UBOOT_SIGN_ENABLE       = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', '1', '0', d)}"
UBOOT_SIGN_KEYDIR       ?= "${SENSORNODE_KEYDIR}"
UBOOT_SIGN_KEYNAME      ?= "${SENSORNODE_KEYNAME}"

FIT_GENERATE_KEYS       = "0"
FIT_SIGN_ALG            = "rsa2048"
FIT_HASH_ALG            = "sha256"

KERNEL_IMAGETYPE        = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'fitImage', 'zImage', d)}"
KERNEL_CLASSES:append   = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', ' kernel-fitimage', '', d)}"
