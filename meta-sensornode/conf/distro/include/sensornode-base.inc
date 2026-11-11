require conf/distro/poky.conf

DISTRO_NAME = "SensorNode"
DISTRO_VERSION = "1.0"

DISTRO_FEATURES:remove = " \
    x11 \
    wayland \
    opengl \
    vulkan \
    bluetooth \
    nfc \
    3g \
    ppp \
    pcmcia \
    wifi \
    alsa \
    pulseaudio \
    gobject-introspection-data \
    pci \
    zeroconf \
    debuginfod \
    multiarch \
"

DISTRO_FEATURES:append = " systemd"

PACKAGECONFIG_DISTRO:pn-qtbase = " \
    linuxfb \
    tslib \
    fontconfig \
"

TOOLCHAIN_TARGET_TASK:append = " \
    libgpiod-dev \
    mosquitto-dev \
    nlohmann-json-dev \
    libsqlite3-dev \
    libubootenv-dev \
    swupdate-dev \
"

VIRTUAL-RUNTIME_init_manager = "systemd"
DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"
VIRTUAL_RUNTIME_initscripts = "systemd-compat-units"

# The kernel and DTB live in the signed FIT at the end of each slot
MACHINE_ESSENTIAL_EXTRA_RDEPENDS:remove = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-verity', 'kernel-image kernel-devicetree', '', d)}"
MACHINE_EXTRA_RRECOMMENDS:remove = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-verity', 'kernel-devicetree', '', d)}"

TMPDIR = "${TOPDIR}/tmp-${DISTRO}"

require conf/include/sensornode-vars.inc
