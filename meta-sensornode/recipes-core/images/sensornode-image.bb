SUMMARY = "SensorNode root filesystem image"

require recipes-core/images/core-image-base.bb
require include/sensornode-image-common.inc

IMAGE_INSTALL:append = " \
    libgpiod-tools libgpiod \
    bbb-static-ip \
    libsqlite3 \
    sensornode-core \
    sensornode-core-settingsd \
    sensornode-core-webd \
"

IMAGE_INSTALL:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-hmi', \
    'sensornode-ui psplash qtbase qtcharts libmosquitto1 ttf-dejavu-sans fontconfig', '', d)}"

IMAGE_INSTALL:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-wifi', 'sensornode-wifi', '', d)}"

BAD_RECOMMENDATIONS += "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-wifi', '', 'rtl8188eu', d)}"

IMAGE_LINGUAS = ""
