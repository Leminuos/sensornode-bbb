FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://0001-bbb-ota.cfg \
    file://0001-bbb-ota-boot-env.patch \
    ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'file://env-writeable-list.cfg file://0002-bbb-env-writeable-list.patch', '', d)} \
"

SENSORNODE_UBOOT_ENV_LOCK_CFG = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'CONFIG_ENV_IS_NOWHERE=y CONFIG_ENV_APPEND=y CONFIG_ENV_WRITEABLE_LIST=y', '', d)}"

# u-boot-tools-native cung cấp mkenvimage để build u-boot-env.raw.
# u-boot-env.raw ở định dạng redundant (-r), ghi giống nhau lên cả hai vùng env.
DEPENDS:append = " u-boot-tools-native"

do_configure:append() {
    printf 'CONFIG_ENV_OFFSET=%s\nCONFIG_ENV_SIZE=%s\nCONFIG_SYS_REDUNDAND_ENVIRONMENT=y\nCONFIG_ENV_OFFSET_REDUND=%s\n' \
        "${SENSORNODE_ENV_OFFSET}" "${SENSORNODE_ENV_SIZE}" "${SENSORNODE_ENV_OFFSET_REDUND}" \
        > ${WORKDIR}/sensornode-env.cfg
    merge_config.sh -m -O ${B} ${B}/.config ${WORKDIR}/sensornode-env.cfg
    oe_runmake -C ${S} O=${B} olddefconfig

    for opt in CONFIG_ENV_OFFSET=${SENSORNODE_ENV_OFFSET} CONFIG_ENV_SIZE=${SENSORNODE_ENV_SIZE} \
               CONFIG_SYS_REDUNDAND_ENVIRONMENT=y CONFIG_ENV_OFFSET_REDUND=${SENSORNODE_ENV_OFFSET_REDUND} \
               ${SENSORNODE_UBOOT_ENV_LOCK_CFG}; do
        if ! grep -qx "$opt" ${B}/.config; then
            bbfatal "U-Boot .config does not contain $opt"
        fi
    done
}

do_compile:append() {
    mkenvimage -r -s ${SENSORNODE_ENV_SIZE} -o ${B}/u-boot-env.raw ${B}/u-boot-initial-env
}

do_deploy:append() {
    install -m 0644 ${B}/u-boot-env.raw ${DEPLOYDIR}/u-boot-env.raw
}
