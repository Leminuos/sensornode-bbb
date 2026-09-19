# Verified boot

Đọc tutorial này giúp ta hiểu:

- Secure boot chain là gì, chuỗi của BBB gồm những mắt xích nào.
- FIT image, cấu hình (configuration) và chữ ký trên cấu hình.
- Yocto sinh key, ký FIT và nhúng public key vào U-Boot như thế nào.
- Các biến và option Kconfig liên quan, từng dòng.

## 1. Secure boot chain

Mỗi giai đoạn boot chỉ được chạy giai đoạn tiếp theo khi được xác thực từ giai đoạn trước đó.

```
ROM (trong SoC)
  └─ nạp MLO (SPL)                              ✗ không kiểm tra
       └─ nạp u-boot.img                        ✗ không kiểm tra
            └─ U-Boot đọc U-Boot env trên thẻ   ✗ env không ký
                 └─ ext4load /boot/fitImage
                      └─ bootm: kiểm tra chữ ký FIT bằng public key trong DTB của U-Boot    ← verified boot
                           └─ kernel + DTB
                                └─ mount rootfs                         ✗ không kiểm tra (chưa có dm-verity)
                                     └─ SWUpdate: kiểm tra chữ ký .swu trước khi ghi slot   ← signed OTA
```

| Chain | Trạng thái | Lý do |
|---|---|---|
| ROM → MLO | Không kiểm tra | AM335x trên BBB là GP device (general purpose): ROM không có chức năng secure boot. Chỉ bản HS (high security) của SoC mới xác thực được SPL |
| MLO → U-Boot | Không kiểm tra | `SPL_SIGN_ENABLE = 0` |
| U-Boot → kernel | Kiểm tra | FIT có chữ ký RSA2048 |
| Kernel → rootfs | Không kiểm tra | Chưa triển khai dm-verity |
| `.swu` → slot | Kiểm tra | Chữ ký CMS trên `sw-description` + sha256 từng file |

## 2. FIT image

FIT (Flattened Image Tree) là định dạng image của U-Boot: một file dạng devicetree gói nhiều thành phần (kernel, DTB, ramdisk) cùng hash và chữ ký.

File mô tả `.its` mà Yocto generate khi build production (`deploy/images/…/fitImage-its-bbb-sensornode`), rút gọn:

```dts
/ {
    images {
        kernel-1 {
            data = /incbin/("linux.bin");
            type = "kernel"; arch = "arm"; os = "linux";
            load = <0x80008000>; entry = <0x80008000>;
            hash-1 { algo = "sha256"; };
        };
        fdt-am335x-boneblack.dtb {
            data = /incbin/("arch/arm/boot/dts/am335x-boneblack.dtb");
            type = "flat_dt";
            load = <0x88000000>;
            hash-1 { algo = "sha256"; };
        };
    };
    configurations {
        default = "conf-am335x-boneblack.dtb";
        conf-am335x-boneblack.dtb {
            kernel = "kernel-1";
            fdt = "fdt-am335x-boneblack.dtb";
            signature-1 {
                algo = "sha256,rsa2048";
                key-name-hint = "dev";
                padding = "pkcs-1.5";
                sign-images = "kernel", "fdt";
            };
        };
    };
};
```

| Phần | Ý nghĩa |
|---|---|
| `images` | Các thành phần, mỗi cái có hash sha256 (`hash-1`) |
| `load`, `entry` | Địa chỉ RAM, lấy từ `UBOOT_LOADADDRESS`, `UBOOT_ENTRYPOINT`, `UBOOT_DTB_LOADADDRESS` trong machine conf |
| `configurations` | Tổ hợp kernel nào đi với DTB nào |
| `signature-1` nằm trong configuration | Chữ ký của tổ hợp kernel + fdt. Attacker không thể ghép kernel signed với một DTB khác |
| `key-name-hint = "dev"` | Tên key, U-Boot tìm node `key-dev` trong DTB của nó |

> [!NOTE] Vì sao machine conf đặt `KERNEL_DEVICETREE = "am335x-boneblack.dtb"`
> Nếu FIT chứa nhiều DTB, cấu hình mặc định là DTB đầu tiên (bone đời đầu), kernel boot với devicetree sai và không có màn hình. Lệnh boot trong U-Boot cũng chỉ rõ `bootm ${kernel_addr_r}#conf-am335x-boneblack.dtb` để không phụ thuộc vào cấu hình mặc định.

## 3. Cấu hình Yocto

### 3.1. Machine conf

[bbb-common.inc](../../meta-sensornode-bsp/conf/machine/include/bbb-common.inc)

```bitbake
UBOOT_SIGN_ENABLE       = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', '1', '0', d)}"
UBOOT_SIGN_KEYDIR       ?= "${TOPDIR}/keys"
UBOOT_SIGN_KEYNAME      ?= "dev"

FIT_GENERATE_KEYS       = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', '1', '0', d)}"
FIT_SIGN_ALG            = "rsa2048"
FIT_HASH_ALG            = "sha256"

KERNEL_IMAGETYPE        = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'fitImage', 'zImage', d)}"
KERNEL_CLASSES:append   = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', ' kernel-fitimage', '', d)}"
```

| Biến | Ý nghĩa |
|---|---|
| `KERNEL_CLASSES` + `kernel-fitimage` | Bật class tạo FIT từ kernel và DTB |
| `KERNEL_IMAGETYPE = fitImage` | File kernel cài vào `/boot` là `fitImage` thay cho `zImage` |
| `UBOOT_SIGN_ENABLE = 1` | Sign FIT và nhúng public key vào DTB của U-Boot |
| `UBOOT_SIGN_KEYDIR` | Thư mục chứa `dev.key` (private) và `dev.crt` (certificate). Mặc định trong build directory |
| `UBOOT_SIGN_KEYNAME` | Tên cặp key → `dev.key`, `dev.crt`, node `key-dev` |
| `FIT_GENERATE_KEYS = 1` | Chưa có key trong thư mục thì tự sinh |
| `FIT_SIGN_ALG`, `FIT_HASH_ALG` | RSA 2048 bit, SHA-256 |

### 3.2. U-Boot

Trong layer BSP, chỉ thêm khi bật `sensornode-secureboot`:

| Dòng | Ý nghĩa |
|---|---|
| `CONFIG_FIT=y` | Hiểu định dạng FIT |
| `CONFIG_FIT_SIGNATURE=y` | Kiểm tra chữ ký FIT. Patch A/B cũng dựa vào option này để chọn `bootm` thay cho `bootz` |
| `CONFIG_FIT_VERBOSE=y` | In chi tiết quá trình kiểm tra lên console |
| `CONFIG_RSA=y`, `CONFIG_RSA_SOFTWARE_EXP=y` | Thuật toán RSA, tính bằng phần mềm (AM335x không có crypto) |
| `CONFIG_OF_CONTROL=y`, `CONFIG_OF_SEPARATE=y` | U-Boot dùng một DTB riêng để mô tả chính nó - public key được đặt trong DTB này |
| `CONFIG_DEFAULT_DEVICE_TREE="am335x-boneblack"` | DTB mặc định của U-Boot |
| `CONFIG_CMD_BOOTM=y`, `CONFIG_BOOTM_LINUX=y` | Lệnh `bootm` boot Linux từ FIT |

### 3.3. Thứ tự các task

```
u-boot       do_compile                     build u-boot-nodtb.bin, u-boot.dtb, u-boot.img
u-boot       do_populate_sysroot            share u-boot.dtb cho kernel
linux-yocto  do_kernel_generate_rsa_keys    FIT_GENERATE_KEYS=1 và chưa có key → sinh dev.key, dev.crt
linux-yocto  do_assemble_fitimage           tạo fit-image.its, mkimage → fitImage
                                            mkimage -F -k <keydir> -K u-boot.dtb -r fitImage
                                            → ký cấu hình và ghi public key vào bản copy u-boot.dtb, đánh dấu required
linux-yocto  do_deploy                      deploy fitImage và u-boot.dtb có key
u-boot       do_deploy                      class uboot-sign: make EXT_DTB=<u-boot.dtb có key>, deploy u-boot.img
image        do_rootfs                      /boot/fitImage vào rootfs
```

Tham số `-r` trong lệnh `mkimage` đặt `required = "conf"` cho key: U-Boot bắt buộc mọi cấu hình FIT phải có chữ ký hợp lệ bằng key này. Đây là điều kiện để verified boot có ý nghĩa.

## 4. Key

| File | Vai trò | Ở đâu |
|---|---|---|
| `${UBOOT_SIGN_KEYDIR}/dev.key` | Private key — ký FIT và ký `.swu` | Chỉ máy build |
| `${UBOOT_SIGN_KEYDIR}/dev.crt` | Certificate X.509 chứa public key | Máy build; public key vào DTB của U-Boot; cert vào `/etc/swupdate/swupdate.pem` |

Hệ quả của việc key nằm trong build directory (`${TOPDIR}/keys`) và `FIT_GENERATE_KEYS = 1`:

- Xoá build directory, build ở máy khác hay CI sạch → **sinh cặp key mới**. Thiết bị đang chạy bản ký bằng key cũ sẽ từ chối `.swu` mới. Muốn build lại ở chỗ khác phải mang theo thư mục `keys/`.
- Private key production không được để trong build directory hay commit vào git. Hướng làm: đặt `UBOOT_SIGN_KEYDIR` trỏ ra thư mục an toàn ngoài repo và `FIT_GENERATE_KEYS = "0"` để không bao giờ tự sinh đè.

