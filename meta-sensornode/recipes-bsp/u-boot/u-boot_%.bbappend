FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://0001-bbb-ota.cfg \
    file://0001-bbb-ota-boot-env.patch \
"

# u-boot-tools-native cung cấp mkenvimage để build u-boot-env.raw
DEPENDS:append = " u-boot-tools-native"

do_configure:append() {
    printf 'CONFIG_ENV_OFFSET=%s\nCONFIG_ENV_SIZE=%s\n' \
        "${SENSORNODE_ENV_OFFSET}" "${SENSORNODE_ENV_SIZE}" > ${WORKDIR}/sensornode-env.cfg
    merge_config.sh -m -O ${B} ${B}/.config ${WORKDIR}/sensornode-env.cfg
    oe_runmake -C ${S} O=${B} olddefconfig

    for opt in CONFIG_ENV_OFFSET=${SENSORNODE_ENV_OFFSET} CONFIG_ENV_SIZE=${SENSORNODE_ENV_SIZE}; do
        if ! grep -qx "$opt" ${B}/.config; then
            bbfatal "U-Boot .config does not contain $opt"
        fi
    done
}

do_compile:append() {
    mkenvimage -s ${SENSORNODE_ENV_SIZE} -o ${B}/u-boot-env.raw ${B}/u-boot-initial-env
}

do_deploy:append() {
    install -m 0644 ${B}/u-boot-env.raw ${DEPLOYDIR}/u-boot-env.raw
}
