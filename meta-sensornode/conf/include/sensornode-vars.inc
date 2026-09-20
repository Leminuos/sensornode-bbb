# Images
SENSORNODE_IMAGE            ?= "sensornode-image"
SENSORNODE_DATA_IMG         ?= "sensornode-data.ext4"

# Partition layout
SENSORNODE_SLOT_A_DEV       ?= "/dev/mmcblk0p1"
SENSORNODE_SLOT_B_DEV       ?= "/dev/mmcblk0p2"
SENSORNODE_SLOT_SIZE_MiB    ?= "160"
SENSORNODE_SLOT_SIZE_KiB     = "${@int(d.getVar('SENSORNODE_SLOT_SIZE_MiB')) * 1024}"
SENSORNODE_DATA_SIZE_MiB    ?= "128"
SENSORNODE_DATA_SIZE_KiB     = "${@int(d.getVar('SENSORNODE_DATA_SIZE_MiB')) * 1024}"

# U-Boot environment on raw MMC
SENSORNODE_ENV_DEV          ?= "/dev/mmcblk0"
SENSORNODE_ENV_OFFSET       ?= "0x260000"
SENSORNODE_ENV_SIZE         ?= "0x20000"
SENSORNODE_ENV_OFFSET_KiB    = "${@int(d.getVar('SENSORNODE_ENV_OFFSET'), 16) // 1024}"

# OTA metadata
OTA_SW_VERSION              ?= "0.1.3"
OTA_HW_REVISION             ?= "1.0"
OTA_BOARD_NAME              ?= "bbb-sensornode"

# Signing keys
SENSORNODE_DEV_KEYDIR       ?= "${@os.path.normpath(os.path.join(d.getVar('LAYERDIR_sensornode'), '../keys/dev'))}"
SENSORNODE_PRODUCT_KEYDIR   ?= "${@os.path.normpath(os.path.join(d.getVar('LAYERDIR_sensornode'), '../keys/product'))}"
SENSORNODE_KEYNAME          ?= "${@os.path.basename(d.getVar('SENSORNODE_KEYDIR'))}"
