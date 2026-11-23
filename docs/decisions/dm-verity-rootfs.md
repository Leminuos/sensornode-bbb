# dm-verity cho rootfs

Tài liệu ghi lại các quyết định thiết kế khi đưa dm-verity vào SensorNode: vì sao chọn từng phương án, các phương án bị loại và hệ quả kéo theo.

## Tóm tắt

| # | Quyết định | Phương án bị loại |
|---|---|---|
| 1 | Mỗi slot có partition boot riêng, bảng GPT | Giữ `fitImage` trong `/boot` của rootfs; một `/boot` dùng chung |
| 2 | Truyền root hash qua initramfs nằm trong FIT | `dm-mod.create=` trên cmdline |
| 3 | Hai image type `verity` và `bootfs` trong `sensornode-image` | Plugin `bootimg-partition`, recipe riêng, `IMAGE_POSTPROCESS_COMMAND` |
| 4 | Tự sinh `.its` và ký FIT ở phía image | `kernel-fitimage.bbclass` với `INITRAMFS_IMAGE` |

## Nền tảng

### Cơ chế dm-verity

Verified boot bảo đảm kernel và DTB đúng là bản đã sign nhưng rootfs thì không được kiểm tra: ai ghi được thẻ SD cũng có thể sửa file trong slot mà board vẫn boot với kernel hợp lệ.

dm-verity là một target của device-mapper. Nó tạo block device ảo `/dev/mapper/root` trên partition thật, mỗi lần đọc một block thì tính hash và so với hash tree dựng sẵn lúc build:

```
block dữ liệu:  [b0][b1][b2] ... [b32111]   <- ext4, mỗi block 4 KiB
                 │   │   │          │
lớp 0:          h0  h1  h2  ...  h32111     <- sha256(salt + block), 32 byte mỗi hash
                 └─┬─┘ ...
lớp 1:            H0 ... H250
lớp 2:               ...
                  │
root hash:     d13e8f09...                  <- 32 byte đại diện cho toàn bộ rootfs
```

Sửa một byte trong ext4 thì hash đổi, kéo theo mọi lớp phía trên. Khi đọc block đó kernel phát hiện không match thì panic hoặc reboot tuỳ cấu hình.

### Yêu cầu về root hash

Hash tree tự nó không chứng minh được gì: ai sửa được rootfs thì cũng tính lại được hash tree. Điểm neo duy nhất là root hash nên root hash phải được bảo vệ. Mọi quyết định bên dưới đều xuất phát từ yêu cầu này.

Secureboot chain mong muốn:

```
u-boot.img (public key)
  └─ bootm kiểm tra signed FIT {kernel, DTB, initramfs}
       └─ initramfs chứa root hash  (được chữ ký FIT bao phủ)
            └─ dm-verity kiểm tra từng block của partition rootfs
```

## Quyết định 1: Partition boot riêng cho từng slot

### Bối cảnh

Layout trước đó:

| Partition | Nội dung |
|---|---|
| `mmcblk0p1` rootA | Rootfs slot A, có `/boot/fitImage` |
| `mmcblk0p2` rootB | Rootfs slot B, có `/boot/fitImage` |
| `mmcblk0p3` data | `/data` |

Kernel và rootfs nằm chung partition nên OTA ghi một file là cập nhật cả hai.

Khi bật dm-verity, layout này tạo thành circular dependency:

```
root hash = hash(rootfs)  = hash(... + /boot/fitImage + ...)
fitImage  = sign(kernel + DTB + root hash)
```

Đưa root hash vào FIT làm FIT đổi, FIT đổi làm rootfs đổi, rootfs đổi làm root hash đổi -> build bao nhiêu lần cũng không ra cặp FIT và root hash khớp nhau.

### Các phương án

| Phương án | Đánh giá |
|---|---|
| Bỏ root hash ra khỏi FIT | Root hash không còn được sign. Kẻ sửa rootfs chỉ cần tính lại hash tree và thay root hash: dm-verity chạy nhưng không bảo vệ gì |
| Một partition `/boot` dùng chung cho hai slot | Không phù hợp với A/B: Bản mới hỏng thì rollback về rootfs cũ nhưng kernel đã là kernel mới mà kernel mới mang root hash và module của rootfs mới nên không mount được rootfs cũ |
| Partition boot riêng cho từng slot | FIT ra khỏi vùng được hash, root hash vẫn trong FIT. OTA ghi và rollback trọn cặp boot + rootfs |

### Lựa chọn

Mỗi slot gồm một partition boot và một partition rootfs.

| Partition | Offset | Kích thước | Nội dung |
|---|---|---|---|
| `mmcblk0p1` bootA | 4 MiB | 16 MiB | ext4, `/fitImage` |
| `mmcblk0p2` rootA | 20 MiB | 156 MiB | ext4 + hash tree |
| `mmcblk0p3` bootB | 176 MiB | 16 MiB | ext4, `/fitImage` |
| `mmcblk0p4` rootB | 192 MiB | 156 MiB | ext4 + hash tree |
| `mmcblk0p5` data | 348 MiB | 128 MiB | `/data` |

```bash
sgdisk -p sensornode-image-bbb-sensornode.wic
```

```
Number  Start (sector)    End (sector)  Size       Code  Name
   1            8192           40959   16.0 MiB    8300  primary
   2           40960          360447   156.0 MiB   8300  primary
   3          360448          393215   16.0 MiB    8300  primary
   4          393216          712703   156.0 MiB   8300  primary
   5          712704          974847   128.0 MiB   8300  primary
```

Hash tree nằm ngay sau rootfs, không có partition riêng. Tách ra thì thêm 2 partition và mỗi lần OTA ghi 3 image thay vì 2, trong khi rootfs và hash tree luôn được build và cài cùng nhau:

```
131530752  sensornode-image-bbb-sensornode.ext4
132571136  sensornode-image-bbb-sensornode.verity     ← ext4 + 1040384 byte hash tree
```

### Hệ quả

- Kernel không còn cài vào rootfs (`/boot` rỗng).
- Mỗi install set của `.swu` ghi hai image: `bootfs.gz` vào partition boot và `verity.gz` vào partition rootfs.
- Đổi layout không OTA được, phải flash lại thẻ.

## Quyết định 2: Truyền root hash qua initramfs

### Bối cảnh

Kernel cần hai thông tin để dựng dm-verity và chúng thay đổi theo hai cách khác nhau:

| Thông tin | Đổi khi nào | Yêu cầu |
|---|---|---|
| Root hash, salt, số block | Mỗi lần build rootfs | Phải được sign, phải đi theo OTA |
| Data/hash device | Theo slot được ghi | Cùng một bản build có thể ghi vào A hoặc B |

### Phương án `dm-mod.create=`

Với `CONFIG_DM_INIT`, kernel tự dựng device-mapper từ cmdline, không cần initramfs:

```
dm-mod.create="root,,,ro,0 <sectors> verity 1 <data_dev> <hash_dev> 4096 4096 <blocks> <hash_start> sha256 <root_hash> <salt>"
root=/dev/dm-0
```

Về cơ chế, kernel 5.15.150 hỗ trợ đủ:

```bash
grep -n "waitfor" drivers/md/dm-init.c | head -2
grep -n '"PARTUUID=\|"PARTLABEL=' init/do_mounts.c
```

```
26:static char *waitfor[DM_MAX_WAITFOR];
32: * dm-mod.waitfor=<device1>[,..,<deviceN>]
287:	if (strncmp(name, "PARTUUID=", 9) == 0)
289:	if (strncmp(name, "PARTLABEL=", 10) == 0)
```

Vướng mắc nằm ở nguồn của cmdline. Kernel nhận một cmdline từ một nguồn và cmdline này phải chứa cả hai thông tin ở bảng trên:

| Nguồn cmdline | Đánh giá |
|---|---|
| `bootargs` trong env U-Boot | Loại. Env mặc định build cứng trong `u-boot.img`, OTA không cập nhật `u-boot.img` nên không mang được root hash mới |
| Thuộc tính trong cấu hình FIT | Loại. U-Boot 2022.01 không có trường bootargs trong FIT được ký và chuyển thẳng cho kernel |
| `/chosen/bootargs` trong DTB của FIT | Dùng được, với điều kiện bên dưới |

DTB nằm trong FIT nên được ký. Theo source U-Boot 2022.01 (`common/fdt_support.c`), U-Boot chỉ ghi đè `/chosen/bootargs` khi env có `bootargs`:

```c
__weak char *board_fdt_chosen_bootargs(void)
{
	return env_get("bootargs");
}
...
	str = board_fdt_chosen_bootargs();

	if (str) {
		err = fdt_setprop(fdt, nodeoffset, "bootargs", str,
				  strlen(str) + 1);
```

Ghi đè ở đây là thay toàn bộ, không nối thêm: U-Boot không chèn được phần thiết bị theo slot vào cmdline đã ký. Cmdline trong DTB vì vậy phải chứa sẵn cả root hash lẫn thiết bị, dẫn tới hai biến thể:

| Biến thể | Đánh giá |
|---|---|
| Build hai FIT (`PARTLABEL=rootA` và `PARTLABEL=rootB`), mỗi bản ký riêng | `.swu` được build trước khi biết thiết bị đang chạy slot nào, board không sửa được FIT đã ký, nên `.swu` phải mang cả hai boot image (khoảng 7 MB mỗi cái) dù mỗi lần cài chỉ ghi một |
| U-Boot tự ghép: tách `bootm` thành `start`/`loados`/`ramdisk`/`fdt`, `fdt get value` lấy root hash từ DTB đã kiểm, ghép `bootargs`, rồi `prep`/`go` | Một FIT duy nhất, nhưng script nằm đúng trên đường bảo mật: đọc nhầm từ bản DTB chưa kiểm là mất toàn bộ tác dụng, và lỗi kiểu này không lộ ra khi test bình thường |

### Lựa chọn

Initramfs nằm trong FIT, tách hai thông tin ra hai nguồn và ghép lại bằng script trong vùng đã ký:

| Thông tin | Nguồn | Được ký |
|---|---|---|
| Root hash, salt, số block | `/etc/verity.env` trong initramfs | Có |
| Data/hash device | `root=/dev/mmcblk0p${root_part}` do U-Boot truyền | Không cần |

`root=` không cần ký: trỏ sang slot khác thì nội dung không khớp root hash và verity từ chối.

```
U-Boot  ota_pick_slot → boot_part=1|3, root_part=2|4
        bootargs = "root=/dev/mmcblk0p${root_part} ro rootwait ... sensornode.slot=${active_slot} panic=10"
        bootm FIT {kernel, dtb, initramfs}          ← kiểm chữ ký cả ba
kernel  giải nén initramfs, chạy /init
/init   . /etc/verity.env                           ← root hash đã ký
        root= trên /proc/cmdline                    ← partition của slot
        dmsetup create root --readonly --table "0 $VERITY_DATA_SECTORS verity 1 $root $root 4096 4096 \
            $VERITY_DATA_BLOCKS $VERITY_HASH_START sha256 $VERITY_ROOT_HASH $VERITY_SALT 1 panic_on_corruption"
        mount -o ro /dev/mapper/root /newroot
        switch_root /newroot /sbin/init             ← /sbin/init là preinit của overlayfs-etc
```

Lỗi ở bất kỳ bước nào làm `/init` thoát, kernel panic, `panic=10` reboot; slot đang chạy thử (`ustate=1`) được U-Boot rollback sau 3 lần như các lỗi boot khác.

So sánh ba phương án:

| | DTB, hai FIT | U-Boot ghép | Initramfs |
|---|---|---|---|
| Boot image trong `.swu` | 2 | 1 | 1 |
| Thành phần thêm | Không | Script U-Boot nhạy cảm bảo mật | Recipe initramfs, script `/init` |
| Nơi ghép root hash và slot | Máy build | Script U-Boot | Script `/init` (đã ký) |
| Xử lý lỗi | Kernel panic khi mount root | Kernel panic khi mount root | Tuỳ script |

### Hệ quả

- Thêm recipe image `sensornode-initramfs` (busybox, glibc, `dmsetup` từ gói `libdevmapper`, `libudev`), đặt `NO_RECOMMENDATIONS = "1"` để không kéo `ldconfig`, `busybox-udhcpc`. Kích thước: `1756664  sensornode-initramfs-bbb-sensornode.cpio.gz`.
- Kernel cần `CONFIG_MD`, `CONFIG_BLK_DEV_DM`, `CONFIG_DM_VERITY`, `CONFIG_CRYPTO_SHA256` built-in (fragment `dm-verity.cfg`): lúc initramfs chạy chưa có `/lib/modules`.
- `/` giờ là `/dev/mapper/root`, nên không suy ra slot từ thiết bị root được nữa. `swupdate -g` không trả về partition, và `09-swupdate-args` cũ rơi vào nhánh `copy1`, tức ghi đè slot A khi đang chạy slot A. U-Boot thêm `sensornode.slot=${active_slot}` vào cmdline; `09-swupdate-args` và otad đọc slot từ tham số này.

## Quyết định 3: Image type `verity` và `bootfs`

### Bối cảnh

Mỗi slot giờ là hai file, và cùng hai file đó phải đi vào cả `.wic` (flash thẻ) lẫn `.swu` (OTA):

| File | Ghi vào |
|---|---|
| `sensornode-image-bbb-sensornode.verity` (dev: `.ext4`) | `rootA` / `rootB` |
| `sensornode-image-bbb-sensornode.bootfs` | `bootA` / `bootB` |

`.bootfs` của production cần root hash, tức chỉ dựng được sau rootfs; còn `.wic` cần `.bootfs`.

### Các phương án

| Phương án | Đánh giá |
|---|---|
| Plugin `bootimg-partition` của wic (`IMAGE_BOOT_FILES`) | Partition boot chỉ tồn tại bên trong `.wic`, không có file riêng cho `.swu`. Plugin chỉ chép file có sẵn, không dựng và ký được FIT chứa root hash |
| Recipe riêng `sensornode-bootfs.bb` | Phải chờ `sensornode-image:do_image_complete` để có root hash; `.wic` của `sensornode-image` lại cần `.bootfs`, mà `do_image_complete` chạy sau `do_image_wic`: vòng. Gỡ vòng phải tách `.wic` sang một recipe nữa và đổi lệnh build |
| `IMAGE_POSTPROCESS_COMMAND` | Chạy lúc `do_image_complete`, sau khi `.wic` đã tạo |
| Image type trong `sensornode-image` | Là task của chính image recipe, sắp thứ tự được với `do_image_ext4` và `do_image_wic` |

### Lựa chọn

Hai class, mỗi class khai báo một image type:

| Class | Image type | Việc làm | Khi nào inherit |
|---|---|---|---|
| [sensornode-verity.bbclass](../../meta-sensornode/classes/sensornode-verity.bbclass) | `verity` | Tạo hash tree và root hash | Chỉ khi bật `sensornode-secureboot` |
| [sensornode-bootfs.bbclass](../../meta-sensornode/classes/sensornode-bootfs.bbclass) | `bootfs` | Đóng kernel vào partition boot; với secure boot, khoá root hash vào FIT đã ký | Luôn luôn |

Tách hai class vì hai việc độc lập: `verity` tạo root hash, `bootfs` khoá nó vào phần được ký. Distro dev cần partition boot (`zImage` + DTB) mà không cần verity.

### Cơ chế khai báo image type

Một class cần ba dòng:

```bitbake
IMAGE_TYPES += "verity"            # đăng ký tên type
IMAGE_TYPEDEP:verity = "ext4"      # type đầu vào
IMAGE_CMD:verity () {              # lệnh shell tạo file
    ... ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.verity
}
```

Image recipe `inherit` class đó và liệt kê type trong `IMAGE_FSTYPES`. Khối `python ()` của `meta/classes/image.bbclass` xử lý từng type:

| Bước | Kết quả |
|---|---|
| Đọc `IMAGE_TYPEDEP:<type>` | Thêm type phụ thuộc; task chạy sau `do_image_<dep>` |
| Lấy `IMAGE_CMD:<type>` | Sinh task `do_image_<type>` chứa đoạn shell đó |
| Type có đuôi conversion (`.gz`, `.xz`...) | Thêm lệnh nén, vd `verity.gz` = tạo `verity` rồi `gzip` |
| Sau task | Tạo symlink `${IMAGE_LINK_NAME}.<type>` trong `${IMGDEPLOYDIR}` |
| `do_image_complete` | Đưa mọi file trong `${IMGDEPLOYDIR}` vào thư mục deploy và sstate |

Trong [sensornode-image-common.inc](../../meta-sensornode/recipes-core/images/include/sensornode-image-common.inc):

```bitbake
IMAGE_FSTYPES = " wic wic.bmap ${SENSORNODE_SLOT_FSTYPE}.gz bootfs.gz"
IMAGE_TYPEDEP:wic += "bootfs ${SENSORNODE_SLOT_FSTYPE}"

inherit sensornode-bootfs ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'sensornode-verity', '', d)}
```

| Dòng | Ý nghĩa |
|---|---|
| `${SENSORNODE_SLOT_FSTYPE}.gz bootfs.gz` | Hai file `.swu` cần (`SWUPDATE_IMAGES_FSTYPES` trong [sensornode-image-swu.bb](../../meta-sensornode/recipes-core/images/sensornode-image-swu.bb)) |
| `IMAGE_TYPEDEP:wic` | wic chờ hai type kia vì wks đọc thẳng `${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.bootfs` và `.verity` |
| `SENSORNODE_SLOT_FSTYPE` | `verity` khi bật secure boot, `ext4` khi không |
| Vị trí `inherit` | Sau `IMAGE_ROOTFS_MAXSIZE` và `IMAGE_OVERHEAD_FACTOR`, để giá trị trong class verity ghi đè |

Chuỗi task của `bitbake sensornode-image` (production):

```
do_rootfs
  └─ do_image_ext4        thư mục rootfs → .ext4
       └─ do_image_verity .ext4 → .verity + .verity.env
            └─ do_image_bootfs  kernel + DTB + initramfs + .verity.env → FIT ký → .bootfs
                 └─ do_image_wic  MLO, u-boot, env, .bootfs, .verity, data → .wic
```

Mũi tên đi một chiều: root hash có sau rootfs, FIT có sau root hash, wic có sau FIT.

### Hệ quả

- `.wic` vẫn do `sensornode-image` tạo, lệnh build không đổi: `bitbake sensornode-image sensornode-image-swu`.
- `.wic` và `.swu` nhận đúng cùng một file `.bootfs` và `.verity`.
- `sensornode-secureboot` bắt buộc đi cùng `sensornode-readonly`: rootfs trên dm-verity chỉ đọc được.

## Quyết định 4: Tự sinh FIT thay cho `kernel-fitimage.bbclass`

### Bối cảnh

Poky kirkstone có `meta/classes/kernel-fitimage.bbclass`, class đang dựng `fitImage` trong thư mục deploy. Đặt `INITRAMFS_IMAGE = "sensornode-initramfs"` và `INITRAMFS_IMAGE_BUNDLE = "0"` là class tự sinh `.its` có `ramdisk-1`, ký và deploy `fitImage-sensornode-initramfs-bbb-sensornode`.

### Vấn đề khi dùng `kernel-fitimage`

**Class gắn vào recipe kernel.**

```bash
grep -n '^addtask' meta/classes/kernel-fitimage.bbclass
```

```
691:addtask assemble_fitimage before do_install after do_compile
705:addtask assemble_fitimage_initramfs before do_deploy after do_bundle_initramfs
752:addtask kernel_generate_rsa_keys before do_assemble_fitimage after do_compile
```

Các hàm `fitimage_assemble`, `fitimage_emit_section_*` lấy file từ `${B}` của kernel (`linux.bin`, `arch/arm/boot/dts/...`) và chèn task vào giữa `do_compile` và `do_deploy` của kernel. Class không dùng lại được trong image recipe.

**FIT trong recipe kernel tạo circular dependency.** Với `INITRAMFS_IMAGE`, class thêm dependency (dòng 35):

```python
d.appendVarFlag('do_assemble_fitimage_initramfs', 'depends', ' ${INITRAMFS_IMAGE}:do_image_complete')
```

Initramfs mang root hash thì chuỗi thành:

```
kernel:do_assemble_fitimage_initramfs
  → sensornode-initramfs:do_image_complete
    → cần root hash → sensornode-image:do_image_complete
      → do_image_wic → cần FIT → kernel:do_deploy
        → sau kernel:do_assemble_fitimage_initramfs        ✗ circular dependency
```

**Nối root hash sau khi ký không được.** Cho `kernel-fitimage` ký FIT với initramfs dùng chung rồi nối `verity.env` vào sau thì hash `ramdisk-1` đổi, chữ ký cấu hình không còn khớp, U-Boot từ chối boot. Muốn sửa phải dựng lại `.its` và ký lại.

### Lựa chọn

Image type `bootfs` tự sinh `.its` và sign ở phía image. `kernel-fitimage` vẫn chạy trong recipe kernel vì hai việc:

- Ký một `fitImage` (kernel + DTB) và nhúng public key vào bản copy `u-boot.dtb` (`mkimage ... -K u-boot.dtb -r`); `uboot-sign` dùng bản này để build `u-boot.img`.
- Deploy `fitImage-linux.bin-bbb-sensornode`, phần kernel mà `bootfs` dùng lại.

### Hệ quả

- `fitImage` của poky được build nhưng không còn được boot.
- `.its` tự sinh theo đúng cấu trúc poky sinh ra (cùng tên node, `UBOOT_LOADADDRESS`, `UBOOT_DTB_LOADADDRESS`, `FIT_HASH_ALG`, `FIT_SIGN_ALG`, `UBOOT_SIGN_KEYNAME`); đối chiếu được với `fitImage-its-bbb-sensornode` trong thư mục deploy.
- Rủi ro viết sai `.its` được chặn lúc build bởi `fit_check_sign`.

## Kiểm chứng

### Máy build

```bash
bitbake sensornode-image sensornode-image-swu
cd tmp-sensornode/deploy/images/bbb-sensornode
```

Hash tree khớp root hash:

```bash
. ./sensornode-image-bbb-sensornode.verity.env
veritysetup verify --no-superblock --hash=sha256 \
    --data-block-size=4096 --hash-block-size=4096 \
    --data-blocks=$VERITY_DATA_BLOCKS --hash-offset=$((VERITY_HASH_START*4096)) \
    --salt=$VERITY_SALT \
    sensornode-image-bbb-sensornode.verity sensornode-image-bbb-sensornode.verity $VERITY_ROOT_HASH && echo VERIFY_OK
```

```
VERIFY_OK
```

Sửa một byte ở block 20000 của bản copy rồi chạy lại cùng lệnh:

```bash
cp sensornode-image-bbb-sensornode.verity /tmp/tamper.img
printf 'X' | dd of=/tmp/tamper.img bs=1 seek=$((20000*4096+7)) conv=notrunc
```

```
Verification failed at position 81920000.
Verification of data area failed.
```

→ `81920000 = 20000 × 4096`: verity chỉ ra đúng block bị sửa.

FIT có chữ ký hợp lệ và mang đúng root hash. Công cụ nằm trong `tmp-sensornode/sysroots-components/x86_64/u-boot-tools-native/usr/bin/`:

```bash
debugfs -R "dump /fitImage fitImage" sensornode-image-bbb-sensornode.bootfs
fit_check_sign -f fitImage -k u-boot.dtb
dumpimage -T flat_dt -p 2 -o ramdisk fitImage
zcat ramdisk | cpio -t | grep -E '^(init|usr/sbin/dmsetup|etc/verity.env)$'
zcat ramdisk | grep -a '^VERITY_ROOT_HASH'
```

```
Signature check OK
Verifying Hash Integrity for node 'conf-am335x-boneblack.dtb'... sha256,rsa2048:product+
Verified OK, loading images
init
usr/sbin/dmsetup
VERITY_ROOT_HASH=d13e8f09cf652508e59afaf2cc74417d1d7769d2c838ec73bbd6906c3481d7db
```

→ Root hash trong ramdisk khớp `.verity.env`. `cpio -t` dừng ở trailer của archive đầu nên không liệt kê `etc/verity.env`; kernel thì đọc tiếp sang archive thứ hai.

Kernel không còn trong rootfs:

```bash
debugfs -R 'ls -l /boot' sensornode-image-bbb-sensornode.ext4
```

```
    101   40755 (2)      0      0    4096  9-Mar-2018 19:34 .
      2   40755 (2)      0      0    4096 23-Nov-2026 22:12 ..
```

Kích thước artifact:

```
  7005745  sensornode-image-bbb-sensornode.bootfs.gz
 44267043  sensornode-image-bbb-sensornode.verity.gz
 51277824  sensornode-image-swu-bbb-sensornode.swu
```

### Board

Chưa chạy. Sau khi flash `sensornode-image-bbb-sensornode.wic`:

```sh
cat /proc/cmdline                          # root=/dev/mmcblk0p2 ... sensornode.slot=A
dmesg | grep verity                        # verity: /dev/mmcblk0p2 mapped, root hash d13e8f09...
mount | grep ' / '                         # /dev/mapper/root ... ro
fw_printenv active_slot ustate
```

Điểm cần xác nhận lần đầu, theo thứ tự dễ hỏng:

1. ROM AM335x boot được thẻ GPT (log SPL xuất hiện trên serial).
2. `/init` dựng được `/dev/mapper/root` (`dmsetup` với `DM_DISABLE_UDEV=1`) và `switch_root` sang `/sbin/init`.
3. Một vòng OTA: ghi p3/p4, boot sang B, `ota-confirm-boot` commit.
