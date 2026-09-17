SUMMARY = "SensorNode root filesystem image"

require recipes-core/images/core-image-base.bb
require include/sensornode-image-common.inc

IMAGE_INSTALL:append = " \
    libgpiod-tools libgpiod \
    bbb-static-ip \
"

IMAGE_INSTALL:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-hmi', \
    'sensornode-ui qtbase qtcharts libmosquitto1 ttf-dejavu-sans fontconfig', '', d)}"

IMAGE_LINGUAS = ""
