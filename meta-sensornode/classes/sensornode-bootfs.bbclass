IMAGE_TYPES += "bootfs"
IMAGE_TYPEDEP:bootfs = "${SENSORNODE_SLOT_FSTYPE}"

SENSORNODE_INITRAMFS ?= "sensornode-initramfs"
SENSORNODE_BOOTFS_SECURE = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', '1', '0', d)}"
SENSORNODE_BOOTFS_DTB = "${@os.path.basename(d.getVar('KERNEL_DEVICETREE').split()[0])}"

do_image_bootfs[depends] += " \
    e2fsprogs-native:do_populate_sysroot \
    virtual/kernel:do_deploy \
    ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', \
        'u-boot-tools-native:do_populate_sysroot dtc-native:do_populate_sysroot \
         virtual/bootloader:do_deploy ${SENSORNODE_INITRAMFS}:do_image_complete', '', d)} \
"

sensornode_bootfs_fit() {
    work=$1
    dtb=${SENSORNODE_BOOTFS_DTB}
    initrd=$work/initramfs.cpio.gz

    cp ${DEPLOY_DIR_IMAGE}/${SENSORNODE_INITRAMFS}-${MACHINE}.cpio.gz $initrd

    install -d $work/verity/etc
    install -m 0644 ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.verity.env $work/verity/etc/verity.env
    (cd $work/verity && printf 'etc\netc/verity.env\n' | cpio -o -H newc -R 0:0 --quiet) | gzip -9n >> $initrd

    cat > $work/fit.its <<EOF
/dts-v1/;

/ {
    description = "SensorNode kernel, DTB and dm-verity initramfs";
    #address-cells = <1>;

    images {
        kernel-1 {
            description = "Linux kernel";
            data = /incbin/("${DEPLOY_DIR_IMAGE}/fitImage-linux.bin-${MACHINE}");
            type = "kernel";
            arch = "arm";
            os = "linux";
            compression = "none";
            load = <${UBOOT_LOADADDRESS}>;
            entry = <${UBOOT_ENTRYPOINT}>;
            hash-1 {
                algo = "${FIT_HASH_ALG}";
            };
        };
        fdt-$dtb {
            description = "Flattened Device Tree blob";
            data = /incbin/("${DEPLOY_DIR_IMAGE}/$dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            load = <${UBOOT_DTB_LOADADDRESS}>;
            hash-1 {
                algo = "${FIT_HASH_ALG}";
            };
        };
        ramdisk-1 {
            description = "dm-verity initramfs";
            data = /incbin/("$initrd");
            type = "ramdisk";
            arch = "arm";
            os = "linux";
            compression = "none";
            hash-1 {
                algo = "${FIT_HASH_ALG}";
            };
        };
    };

    configurations {
        default = "conf-$dtb";
        conf-$dtb {
            description = "Linux kernel, FDT blob, dm-verity initramfs";
            kernel = "kernel-1";
            fdt = "fdt-$dtb";
            ramdisk = "ramdisk-1";
            hash-1 {
                algo = "${FIT_HASH_ALG}";
            };
            signature-1 {
                algo = "${FIT_HASH_ALG},${FIT_SIGN_ALG}";
                key-name-hint = "${UBOOT_SIGN_KEYNAME}";
                padding = "pkcs-1.5";
                sign-images = "kernel", "fdt", "ramdisk";
            };
        };
    };
};
EOF

    uboot-mkimage -f $work/fit.its -k ${UBOOT_SIGN_KEYDIR} $work/root/fitImage
    uboot-fit_check_sign -f $work/root/fitImage -k ${DEPLOY_DIR_IMAGE}/${UBOOT_DTB_BINARY}
}

IMAGE_CMD:bootfs () {
    work=${WORKDIR}/bootfs
    out=${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.bootfs

    rm -rf $work
    install -d $work/root

    if [ "${SENSORNODE_BOOTFS_SECURE}" = "1" ]; then
        sensornode_bootfs_fit $work
    else
        install -m 0644 ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} $work/root/${KERNEL_IMAGETYPE}
        install -m 0644 ${DEPLOY_DIR_IMAGE}/${SENSORNODE_BOOTFS_DTB} $work/root/${SENSORNODE_BOOTFS_DTB}
    fi

    rm -f $out
    mke2fs -F -q -t ext4 -O ^has_journal -E root_owner=0:0 -d $work/root $out ${SENSORNODE_BOOT_SIZE_KiB}k
}
