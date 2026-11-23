IMAGE_TYPES += "bootfs"
IMAGE_TYPEDEP:bootfs = "${SENSORNODE_SLOT_FSTYPE}"

SENSORNODE_BOOTFS_DTB = "${@os.path.basename(d.getVar('KERNEL_DEVICETREE').split()[0])}"

do_image_bootfs[depends] += " \
    e2fsprogs-native:do_populate_sysroot \
    virtual/kernel:do_deploy \
"

IMAGE_CMD:bootfs () {
    work=${WORKDIR}/bootfs
    out=${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.bootfs

    rm -rf $work
    install -d $work/root

    install -m 0644 ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} $work/root/${KERNEL_IMAGETYPE}
    install -m 0644 ${DEPLOY_DIR_IMAGE}/${SENSORNODE_BOOTFS_DTB} $work/root/${SENSORNODE_BOOTFS_DTB}

    rm -f $out
    mke2fs -F -q -t ext4 -O ^has_journal -E root_owner=0:0 -d $work/root $out ${SENSORNODE_BOOT_SIZE_KiB}k
}
