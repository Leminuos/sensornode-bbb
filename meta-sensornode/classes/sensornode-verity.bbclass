IMAGE_TYPES += "verity"
IMAGE_TYPEDEP:verity = "ext4"

EXTRA_IMAGECMD:ext4 = "-b 4096 -i 8192 -m 0 -O ^has_journal"
IMAGE_ROOTFS_ALIGNMENT = "4"
IMAGE_OVERHEAD_FACTOR = "1.0"
IMAGE_ROOTFS_EXTRA_SPACE = "8192"

# Hash tree nằm chung partition với ext4 và chiếm khoảng 1/128 kích thước ext4
IMAGE_ROOTFS_MAXSIZE = "${@int(d.getVar('SENSORNODE_SLOT_SIZE_KiB')) * 127 // 128}"

do_image_verity[depends] += "cryptsetup-native:do_populate_sysroot"

IMAGE_CMD:verity () {
    src=${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.ext4
    out=${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.verity
    env=${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.verity.env
    log=${WORKDIR}/verity-format.txt
    slot_bytes=$(expr ${SENSORNODE_SLOT_SIZE_KiB} \* 1024)

    data_size=$(stat -c %s $src)
    if [ $(expr $data_size % 4096) -ne 0 ]; then
        bbfatal "ext4 image size $data_size is not a multiple of 4096"
    fi
    data_blocks=$(expr $data_size / 4096)

    # Copy .ext4 sang .verity
    cp --sparse=always $src $out

    # Dựng hash tree 
    salt=$(sha256sum $src | cut -d' ' -f1)
    veritysetup format --no-superblock --hash=sha256 \
        --data-block-size=4096 --hash-block-size=4096 \
        --data-blocks=$data_blocks --hash-offset=$data_size \
        --salt=$salt $out $out > $log
    cat $log

    root_hash=$(sed -n 's/^Root hash:[[:space:]]*//p' $log)
    if [ -z "$root_hash" ]; then
        bbfatal "veritysetup did not report a root hash"
    fi

    total=$(stat -c %s $out)
    if [ $total -gt $slot_bytes ]; then
        bbfatal "ext4 + hash tree ($total bytes) is larger than the slot ($slot_bytes bytes)"
    fi
    bbnote "verity: data $data_size bytes, hash tree $(expr $total - $data_size) bytes, slot $slot_bytes bytes"

    # ghi tham số ra .verity.env
    cat > $env <<EOF
VERITY_DATA_SECTORS=$(expr $data_size / 512)
VERITY_DATA_BLOCKS=$data_blocks
VERITY_HASH_START=$data_blocks
VERITY_ROOT_HASH=$root_hash
VERITY_SALT=$salt
EOF
    ln -sf $(basename $env) ${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.verity.env
}
