do_install:append() {
    install -d ${D}${sysconfdir}
    printf '# Device          Offset      Size\n%s      %s    %s\n' \
        "${SENSORNODE_ENV_DEV}" "${SENSORNODE_ENV_OFFSET}" "${SENSORNODE_ENV_SIZE}" \
        > ${D}${sysconfdir}/fw_env.config
    chmod 0644 ${D}${sysconfdir}/fw_env.config
}

FILES:${PN}:append = " ${sysconfdir}/fw_env.config"
