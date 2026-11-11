# Image type "verity": the raw content of one A/B slot.
#
#   0                     hash start            FIT offset          slot end
#   | ext4 (4 KiB blocks) | dm-verity hash tree | ... | signed FIT  |
#
# The FIT holds the kernel, the DTB and the verity parameters (root hash,
# salt, sizes) as properties of its configuration node. U-Boot reads them
# from the FIT, bootm checks the config signature, and the kernel maps the
# slot with dm-mod.create.

IMAGE_TYPES += "verity"
IMAGE_TYPEDEP:verity = "ext4"
IMAGE_TYPEDEP:wic += "verity"
IMAGE_FSTYPES:append = " verity.gz"

# Block 4 KiB khớp với block của dm-verity; rootfs không bao giờ được ghi nên không cần journal
EXTRA_IMAGECMD:ext4 = "-i 4096 -b 4096 -O ^has_journal"
IMAGE_ROOTFS_ALIGNMENT = "4"

# Kernel nằm trong FIT ở đuôi slot, không cần trong /boot
BAD_RECOMMENDATIONS += "kernel-image-*"

do_image_verity[depends] += " \
    cryptsetup-native:do_populate_sysroot \
    u-boot-tools-native:do_populate_sysroot \
    dtc-native:do_populate_sysroot \
    virtual/kernel:do_deploy \
    virtual/bootloader:do_deploy \
"

SENSORNODE_VERITY_KERNEL = "${DEPLOY_DIR_IMAGE}/fitImage-linux.bin-${MACHINE}"
SENSORNODE_VERITY_DTB    = "${@os.path.basename(d.getVar('KERNEL_DEVICETREE').split()[0])}"
SENSORNODE_VERITY_UBOOT_DTB = "${DEPLOY_DIR_IMAGE}/${UBOOT_DTB_BINARY}"

IMAGE_CMD:verity () {
    src=${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.ext4
    out=${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.verity
    work=${WORKDIR}/verity
    fit_offset=$(expr ${SENSORNODE_VERITY_FIT_OFFSET_KiB} \* 1024)
    fit_max=$(expr ${SENSORNODE_VERITY_FIT_SIZE_MiB} \* 1048576)

    rm -rf $work
    mkdir -p $work
    cp $src $out

    data_size=$(stat -c %s $out)
    if [ $(expr $data_size % 4096) -ne 0 ]; then
        bbfatal "ext4 image size $data_size is not a multiple of 4096"
    fi
    data_blocks=$(expr $data_size / 4096)

    salt=$(sha256sum $src | cut -d' ' -f1)
    veritysetup format --no-superblock --hash=sha256 \
        --data-block-size=4096 --hash-block-size=4096 \
        --data-blocks=$data_blocks --hash-offset=$data_size \
        --salt=$salt $out $out > $work/format.txt
    cat $work/format.txt

    root_hash=$(sed -n 's/^Root hash:[[:space:]]*//p' $work/format.txt)
    if [ -z "$root_hash" ]; then
        bbfatal "veritysetup did not report a root hash"
    fi

    hash_end=$(stat -c %s $out)
    if [ $hash_end -gt $fit_offset ]; then
        bbfatal "ext4 + hash tree ($hash_end bytes) overlaps the FIT at $fit_offset"
    fi

    cat > $work/verity.its <<EOF
/dts-v1/;

/ {
    description = "SensorNode kernel for a dm-verity rootfs";
    #address-cells = <1>;

    images {
        kernel-1 {
            description = "Linux kernel";
            data = /incbin/("${SENSORNODE_VERITY_KERNEL}");
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
        fdt-${SENSORNODE_VERITY_DTB} {
            description = "Flattened Device Tree blob";
            data = /incbin/("${DEPLOY_DIR_IMAGE}/${SENSORNODE_VERITY_DTB}");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            load = <${UBOOT_DTB_LOADADDRESS}>;
            hash-1 {
                algo = "${FIT_HASH_ALG}";
            };
        };
    };

    configurations {
        default = "conf-${SENSORNODE_VERITY_DTB}";
        conf-${SENSORNODE_VERITY_DTB} {
            description = "Linux kernel, FDT blob, dm-verity rootfs";
            kernel = "kernel-1";
            fdt = "fdt-${SENSORNODE_VERITY_DTB}";
            sensornode,verity-sectors = "$(expr $data_size / 512)";
            sensornode,verity-data-blocks = "$data_blocks";
            sensornode,verity-hash-start = "$data_blocks";
            sensornode,verity-root-hash = "$root_hash";
            sensornode,verity-salt = "$salt";
            hash-1 {
                algo = "${FIT_HASH_ALG}";
            };
            signature-1 {
                algo = "${FIT_HASH_ALG},${FIT_SIGN_ALG}";
                key-name-hint = "${UBOOT_SIGN_KEYNAME}";
                padding = "pkcs-1.5";
                sign-images = "kernel", "fdt";
            };
        };
    };
};
EOF

    uboot-mkimage -f $work/verity.its -k ${UBOOT_SIGN_KEYDIR} $work/verity.itb
    uboot-fit_check_sign -f $work/verity.itb -k ${SENSORNODE_VERITY_UBOOT_DTB}

    fit_size=$(stat -c %s $work/verity.itb)
    if [ $fit_size -gt $fit_max ]; then
        bbfatal "FIT ($fit_size bytes) does not fit in ${SENSORNODE_VERITY_FIT_SIZE_MiB} MiB"
    fi

    dd if=$work/verity.itb of=$out bs=1024 seek=${SENSORNODE_VERITY_FIT_OFFSET_KiB} conv=notrunc
}
