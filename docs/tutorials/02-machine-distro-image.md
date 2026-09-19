# MACHINE, DISTRO, IMAGE

Build Yocto được quyết định bởi ba câu hỏi độc lập: **phần cứng là gì** (MACHINE), **chính sách phần mềm là gì** (DISTRO), **cài những gì vào rootfs** (IMAGE). Tutorial này giúp ta hiểu được:

- Một dòng cấu hình nên đặt ở machine conf, distro conf, image recipe hay `local.conf`.
- Thứ tự bitbake đọc các file `.conf` và vì sao nó ảnh hưởng `?=` / `=`.
- Machine `bbb-sensornode` được xây từ `beaglebone-yocto` ra sao.
- Distro `sensornode` và `sensornode-dev` khác nhau ở đâu, feature flag được đọc thế nào.
- Image gom package từ những nguồn nào.
- Vì sao có file `sensornode-vars.inc`.

## 1. Ba tầng

| Tầng | Câu hỏi | File trong dự án | Ví dụ nội dung |
|---|---|---|---|
| MACHINE | Chạy trên board nào, chip gì, bootloader/kernel/devicetree nào? | `meta-sensornode-bsp/conf/machine/` | `KERNEL_DEVICETREE`, `UBOOT_LOADADDRESS`, module ILI9341 |
| DISTRO | Chính sách hệ điều hành: init system, feature bật/tắt, security? | `meta-sensornode/conf/distro/` | `systemd`, bỏ `x11`, bật `sensornode-secureboot` |
| IMAGE | Rootfs cuối cùng gồm package nào, định dạng gì, layout thẻ SD ra sao? | `meta-sensornode/recipes-core/images/` | `IMAGE_INSTALL`, `IMAGE_FSTYPES`, `WKS_FILE` |
| `local.conf` | Tuỳ chọn của máy build | build directory | `DL_DIR`, `BB_NUMBER_THREADS`, `MACHINE ?=`, `DISTRO ?=` |

Mẹo phân loại một dòng cấu hình:

- Nếu thay board khác mà dòng đó phải đổi → MACHINE.
- Nếu muốn làm bản dev và bản production trên cùng board → DISTRO.
- Nếu làm image thứ hai (ví dụ image factory test) trên cùng board và cùng distro mà dòng đó khác → IMAGE.
- Nếu chỉ liên quan máy tính đang build → `local.conf`.

## 2. Thứ tự parse cấu hình

`poky/meta/conf/bitbake.conf` include các file theo thứ tự:

```
local.conf  ->  conf/machine/${MACHINE}.conf  ->  conf/distro/${DISTRO}.conf
```

Sau đó mới tới từng recipe và bbappend, class, image. Hệ quả với toán tử gán:

| Trường hợp | Kết quả |
|---|---|
| `local.conf` gán `=`, distro gán `?=` | Giá trị `local.conf` thắng |
| `local.conf` gán `=`, distro gán `=` | Giá trị distro thắng vì được đọc sau |
| machine gán `?=`, distro gán `=` | Distro thắng |

Vì vậy [sensornode-vars.inc](../../meta-sensornode/conf/include/sensornode-vars.inc) dùng `?=` cho mọi giá trị người dùng có thể muốn đổi: đặt `SENSORNODE_SLOT_SIZE_MiB = "200"` trong `local.conf` là đủ. Ngược lại `TMPDIR` trong distro dùng `=` nhằm cố ý không cho `local.conf` gộp hai distro vào một `TMPDIR`.

## 3. Tầng machine

Machine conf được tách thành 3 file để phần dùng lại được không lẫn với phần riêng:

```
meta-sensornode-bsp/conf/machine/
├── bbb-sensornode.conf            # entry: require 2 file dưới
└── include/
    ├── bbb-common.inc             # mọi thứ về BeagleBone Black
    └── sensornode-hw.inc          # linh kiện SensorNode gắn thêm vào BBB
```

[bbb-sensornode.conf](../../meta-sensornode-bsp/conf/machine/bbb-sensornode.conf):

```bitbake
#@TYPE: Machine
#@NAME: bbb-sensornode
#@DESCRIPTION: BeagleBone Black with the SensorNode display and sensor board

require conf/machine/include/bbb-common.inc
require conf/machine/include/sensornode-hw.inc
```

Tên file quyết định tên machine: `MACHINE = "bbb-sensornode"` → bitbake tìm `conf/machine/bbb-sensornode.conf` trong mọi layer.

> [!TIP]
> Tên machine dùng tiền tố board trước (`bbb-sensornode`) theo convention Yocto (`beaglebone-yocto`, `raspberrypi4-64`).

### 3.1. `bbb-common.inc`

```bitbake
require conf/machine/beaglebone-yocto.conf

MACHINEOVERRIDES =. "beaglebone-yocto:"
```

- Kế thừa toàn bộ machine `beaglebone-yocto` của poky
- `MACHINEOVERRIDES =. "beaglebone-yocto:"` thêm `beaglebone-yocto` vào danh sách override. Mọi `...:beaglebone-yocto` trong layer upstream (ví dụ bbappend của linux-yocto có `KMACHINE:beaglebone-yocto`) vẫn áp dụng cho machine mới. Dùng `=.` để ghép trước và không thêm dấu cách, vì `MACHINEOVERRIDES` là danh sách phân cách bằng `:`.

```bitbake
KERNEL_DEVICETREE       = "am335x-boneblack.dtb"
```

`beaglebone-yocto` build DTB cho bone, boneblack, bonegreen. Dòng này chỉ lấy boneblack DTB làm kernel devicetree.

```bitbake
UBOOT_DTB_BINARY        = "u-boot.dtb"
UBOOT_NODTB_BINARY      = "u-boot-nodtb.bin"
UBOOT_ENTRYPOINT        = "0x80008000"
UBOOT_LOADADDRESS       = "0x80008000"
UBOOT_DTB_LOADADDRESS   = "0x88000000"
```

Các thuộc tính của SoC/board nên nằm ở machine.

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

Khả năng verified boot là của board còn bật hay không là quyết định của distro.

### 3.2. `sensornode-hw.inc`

```bitbake
MACHINE_EXTRA_RRECOMMENDS += " \
    kernel-module-ili9341 \
    kernel-module-drm-mipi-dbi \
"
```

Board có màn ILI9341 thì cần driver cho nó - đây là sự thật về phần cứng, không phải lựa chọn của image. `MACHINE_EXTRA_RRECOMMENDS` được `packagegroup-base` kéo vào, mà `core-image-base` có packagegroup này. Mọi image dựa trên `core-image-base` cho machine này đều tự có module, không phải lặp lại trong từng image recipe.

"RRECOMMENDS" nghĩa là khuyến nghị runtime: nếu sau này driver được build thẳng vào kernel (`=y`) và không còn package module riêng, build không bị lỗi.

## 4. Tầng distro

```
meta-sensornode/conf/distro/
├── include/sensornode-base.inc    # chính sách chung
├── sensornode.conf                # production
└── sensornode-dev.conf            # development
```

### 4.1. `sensornode-base.inc`

```bitbake
require conf/distro/poky.conf

DISTRO_NAME = "SensorNode"
DISTRO_VERSION = "1.0"
```

Kế thừa distro `poky` rồi chỉnh.

```bitbake
DISTRO_FEATURES:remove = " x11 wayland opengl vulkan bluetooth nfc 3g ppp pcmcia wifi alsa pulseaudio gobject-introspection-data pci zeroconf debuginfod multiarch "
DISTRO_FEATURES:append = " systemd sensornode-hmi "
```

`DISTRO_FEATURES` là danh sách từ khoá mà recipe đọc để quyết định bật tính năng. Bỏ `x11` thì Qt, gstreamer...không build phần X11. Bỏ `bluetooth` thì bluez không vào image. Mỗi feature bỏ đi là ít package, ít thời gian build, rootfs nhỏ hơn.

```bitbake
PACKAGECONFIG_DISTRO:pn-qtbase = " linuxfb tslib fontconfig "
```

`PACKAGECONFIG` là tuỳ chọn build của từng recipe. `:pn-qtbase` giới hạn dòng này chỉ cho recipe `qtbase`: bật backend `linuxfb` (vẽ thẳng lên `/dev/fb0`), input `tslib` (touch), `fontconfig`.

```bitbake
TOOLCHAIN_TARGET_TASK:append = " libgpiod-dev mosquitto-dev "
```

Thêm header vào SDK (`bitbake meta-toolchain-qt5`) để cross-compile app ngoài Yocto.

```bitbake
VIRTUAL-RUNTIME_init_manager = "systemd"
DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"
VIRTUAL_RUNTIME_initscripts = "systemd-compat-units"
```

Dùng systemd làm init và `BACKFILL_CONSIDERED` ngăn poky tự thêm lại feature `sysvinit`.

```bitbake
TMPDIR = "${TOPDIR}/tmp-${DISTRO}"

require conf/include/sensornode-vars.inc
```

`TMPDIR` riêng cho từng distro: build dev nằm ở `tmp-sensornode-dev/`, production ở `tmp-sensornode/`. Hai distro cùng machine nhưng khác cấu hình, nếu dùng chung `TMPDIR` thì mỗi lần đổi distro, bitbake xoá và dựng lại rất nhiều thứ. `sstate-cache` và `downloads` vẫn dùng chung nên không tốn thêm thời gian build những phần giống nhau.

### 4.2. Hai biến thể

[sensornode.conf](../../meta-sensornode/conf/distro/sensornode.conf) — production:

```bitbake
require conf/distro/include/sensornode-base.inc
DISTRO = "sensornode"
DISTRO_FEATURES:append = " sensornode-ota sensornode-secureboot sensornode-readonly "
```

[sensornode-dev.conf](../../meta-sensornode/conf/distro/sensornode-dev.conf) — development:

```bitbake
require conf/distro/include/sensornode-base.inc
DISTRO = "sensornode-dev"
DISTRO_FEATURES:append = " sensornode-ota sensornode-debug "
```

Hai file chỉ khác nhau ở danh sách feature. Không có biến tự đặt kiểu `DEVELOPMENT_BUILD = "1"` trong `local.conf`: mọi khác biệt dev/production đều suy ra từ distro.

## 5. Tầng image

> [!WARNING]
>Không dùng tiền tố `core-image-` cho image của dự án, tiền tố đó là quy ước dành cho oe-core.

### 5.1. Image recipe

[sensornode-image.bb](../../meta-sensornode/recipes-core/images/sensornode-image.bb):

```bitbake
SUMMARY = "SensorNode root filesystem image"

require recipes-core/images/core-image-base.bb
require include/sensornode-image-common.inc

IMAGE_INSTALL:append = " libgpiod-tools libgpiod bbb-static-ip "

IMAGE_INSTALL:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-hmi', \
    'sensornode-ui qtbase qtcharts libmosquitto1 ttf-dejavu-sans fontconfig', '', d)}"

IMAGE_LINGUAS = ""
```

- `require include/sensornode-image-common.inc`: logic dùng chung cho mọi image của dự án. Nếu sau này có image thứ hai (ví dụ `sensornode-image-factory`), nó cũng `require` file này.
- `IMAGE_LINGUAS = ""`: không cài locale, tiết kiệm vài MB.

### 5.2. `IMAGE_INSTALL` và `IMAGE_FEATURES`

| Biến | Nhận | Ví dụ |
|---|---|---|
| `IMAGE_INSTALL` | Tên package | `swupdate`, `sensornode-ui` |
| `IMAGE_FEATURES` | Tên tính năng image do class `image`/`core-image` định nghĩa. Mỗi tính năng có thể kéo package và/hoặc chạy hook trên rootfs | `read-only-rootfs` (sửa fstab), `debug-tweaks` (root không mật khẩu), `ssh-server-openssh` (kéo `packagegroup-core-ssh-openssh`) |

Trong `sensornode-image-common.inc`, mỗi feature distro được dịch sang cấu hình image:

```bitbake
IMAGE_INSTALL:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-ota', \
    'swupdate swupdate-www libubootenv-bin ota-confirm-boot', '', d)}"

IMAGE_FEATURES:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-readonly', \
    'read-only-rootfs', '', d)}"

IMAGE_FEATURES:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-debug', \
    'debug-tweaks ssh-server-openssh', '', d)}"

IMAGE_INSTALL:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-debug', \
    'i2c-tools evtest strace lsof mosquitto-clients inotify-tools \
     tslib tslib-calibrate tslib-tests systemd-analyze', '', d)}"
```

Dòng bảo vệ bản production:

```bitbake
IMAGE_FEATURES:remove = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-debug', '', \
    'debug-tweaks empty-root-password allow-empty-password allow-root-login \
     post-install-logging ssh-server-openssh ssh-server-dropbear', d)}"
```

`local.conf` mẫu của poky có sẵn `EXTRA_IMAGE_FEATURES ?= "debug-tweaks"`. Nếu không có dòng `:remove` này, bản production build trên một build directory mặc định vẫn cho đăng nhập root không mật khẩu. `:remove` chạy sau cùng nên thắng mọi cách thêm vào.

### 5.3. Ba cách đưa package vào image

| Cách | Khi nào dùng | Ví dụ |
|---|---|---|
| `MACHINE_EXTRA_RRECOMMENDS` (machine) | Package cần vì phần cứng của board | module ILI9341 |
| `IMAGE_INSTALL` (image) | Package là nội dung của sản phẩm | `sensornode-ui`, `swupdate` |
| `RDEPENDS:${PN}` (recipe) | Package A không chạy được nếu thiếu B | app cần `qtbase-plugins` |

## 6. `sensornode-vars.inc`

Vài giá trị được nhiều thành phần khác nhau cùng dùng: offset env U-Boot có trong Kconfig của U-Boot, trong `fw_env.config` của userspace, trong `--align` của wks và trong `mkenvimage`. Nếu viết tay ở 4 chỗ, sửa sót một chỗ thì env đọc/ghi sai địa chỉ — lỗi rất khó đoán.

[sensornode-vars.inc](../../meta-sensornode/conf/include/sensornode-vars.inc) được `require` từ distro base nên mọi recipe, bbappend, class và file `.wks.in` đều đọc được:

```bitbake
SENSORNODE_SLOT_SIZE_MiB    ?= "160"
SENSORNODE_SLOT_SIZE_KiB     = "${@int(d.getVar('SENSORNODE_SLOT_SIZE_MiB')) * 1024}"
SENSORNODE_ENV_OFFSET       ?= "0x260000"
SENSORNODE_ENV_OFFSET_KiB    = "${@int(d.getVar('SENSORNODE_ENV_OFFSET'), 16) // 1024}"
```

## 7. Kiểm tra bằng lệnh

```bash
# Distro đang dùng và feature đang bật
bitbake -e sensornode-image | grep -E '^(DISTRO|DISTRO_FEATURES)='

# Image feature cuối cùng
DISTRO=sensornode bitbake -e sensornode-image | grep ^IMAGE_FEATURES=
DISTRO=sensornode-dev bitbake -e sensornode-image | grep ^IMAGE_FEATURES=
```
