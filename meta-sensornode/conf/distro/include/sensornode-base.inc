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
    nfs \
"

DISTRO_FEATURES:append = " systemd"

# journald đã lưu log persistent, không cần busybox syslogd/klogd.
VIRTUAL-RUNTIME_base-utils-syslog = ""

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

# Kernel và DTB nằm trên partition boot của mỗi slot, không cài vào rootfs.
MACHINE_ESSENTIAL_EXTRA_RDEPENDS:remove = "kernel-image kernel-devicetree"
MACHINE_EXTRA_RRECOMMENDS:remove = "kernel-devicetree"

TMPDIR = "${TOPDIR}/tmp-${DISTRO}"

require conf/include/sensornode-vars.inc
