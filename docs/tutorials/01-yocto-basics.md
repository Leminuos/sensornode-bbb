# Yocto căn bản

Tutorial này giúp đọc hiểu bất kỳ file nào trong `meta-sensornode-bsp/` và `meta-sensornode/`. Mọi ví dụ đều lấy từ chính repo, không dùng ví dụ giả định. Đọc xong, ta sẽ hiểu được:
- Layer là gì và `layer.conf` khai báo những gì.
- Cấu trúc một recipe `.bb`, các biến và toán tử gán.
- Task là gì, recipe đi qua những task nào từ source tới package.
- `.bbappend` sửa recipe của layer khác như thế nào.
- Các lệnh để tự điều tra khi không chắc.

## 1. Bitbake, recipe và layer

**bitbake** là công cụ thực thi. Nó đọc metadata (file `.conf`, `.bb`, `.bbappend`, `.bbclass`, `.inc`), tính ra danh sách việc cần làm rồi chạy chúng theo thứ tự phụ thuộc.

**Recipe** (`.bb`) mô tả cách tạo ra một phần mềm: lấy source ở đâu, build thế nào, cài file nào, đóng thành package gì. Ví dụ `sensornode-data-mount.bb` mô tả cách cài unit `data.mount` vào rootfs.

**Layer** là một thư mục gom các recipe và config liên quan. Dự án có 2 layer:

| Layer | Chứa |
|---|---|
| `meta-sensornode-bsp` | Phần cứng: machine conf, kernel (devicetree + config), U-Boot verified boot |
| `meta-sensornode` | Sản phẩm: distro, image, app Qt, OTA, `/data`, network |

Tách như vậy để layer BSP có thể dùng lại cho sản phẩm khác trên cùng board và layer sản phẩm không phải biết chi tiết chân pin.

## 2. File `layer.conf`

Mở [meta-sensornode/conf/layer.conf](../../meta-sensornode/conf/layer.conf):

```bitbake
BBPATH .= ":${LAYERDIR}"

BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
            ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "sensornode"
BBFILE_PATTERN_sensornode = "^${LAYERDIR}/"
BBFILE_PRIORITY_sensornode = "10"

LAYERVERSION_sensornode        = "1"
LAYERDEPENDS_sensornode        = "core yocto openembedded-layer networking-layer qt5-layer swupdate sensornode-bsp"
LAYERSERIES_COMPAT_sensornode  = "kirkstone"
```

| Dòng | Ý nghĩa |
|---|---|
| `BBPATH .= ":${LAYERDIR}"` | Thêm thư mục layer vào đường dẫn tìm kiếm. Nhờ vậy `require conf/include/sensornode-vars.inc` hay file `wic/*.wks.in` được tìm thấy mà không cần đường dẫn tuyệt đối |
| `BBFILES` | Pattern đường dẫn các recipe của layer. Recipe phải nằm đúng 2 cấp `recipes-<nhóm>/<tên>/`, đặt sâu hơn sẽ bị bỏ qua |
| `BBFILE_COLLECTIONS` | Tên định danh của layer (`sensornode`). Các layer khác dùng tên này, không dùng tên thư mục |
| `BBFILE_PATTERN_sensornode` | Regex xác định file nào thuộc layer này |
| `BBFILE_PRIORITY_sensornode` | Độ ưu tiên. Khi hai layer cùng có recipe tên giống nhau thì layer ưu tiên cao thắng và các `.bbappend` cũng được áp dụng theo thứ tự ưu tiên |
| `LAYERVERSION_sensornode` | Version của layer để layer khác có thể yêu cầu version tối thiểu |
| `LAYERDEPENDS_sensornode` | Các layer bắt buộc phải có trong `bblers.conf`. Thiếu là bitbake dừng ngay |
| `LAYERSERIES_COMPAT_sensornode` | Series Yocto mà layer tương thích |

Layer BSP chỉ phụ thuộc `core yoctobsp`: nó không dùng gì của Qt, MQTT hay SWUpdate. Layer product phụ thuộc BSP, không có chiều ngược lại.

## 3. Bóc tách một recipe

Recipe đơn giản nhất của dự án - [sensornode-data-mount.bb](../../meta-sensornode/recipes-core/sensornode-data/sensornode-data-mount.bb):

```bitbake
SUMMARY = "systemd mount unit for the /data partition"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://data.mount"

S = "${WORKDIR}"

inherit systemd allarch

SYSTEMD_SERVICE:${PN} = "data.mount"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/data.mount ${D}${systemd_system_unitdir}/data.mount
}

FILES:${PN} = "${systemd_system_unitdir}/data.mount"
```

Đọc từng khối:

**Tên và version lấy từ tên file.** `sensornode-data-mount.bb` → `PN = sensornode-data-mount`. File dạng `sensornode-ui_1.0.bb` → `PN = sensornode-ui`, `PV = 1.0`. Không có `_` thì `PV` mặc định là `1.0`.

**License.** `LICENSE` khai báo loại license. `LIC_FILES_CHKSUM` trỏ tới file license và md5 của nó. Nếu nội dung file license mismatch, build dừng, buộc người sửa phải xem lại license. Recipe app dùng `file://LICENSE;md5=...` vì license nằm trong source. Các recipe nhỏ dùng bản MIT chung của poky.

**`SRC_URI` - lấy source ở đâu.**

| Dạng | Ví dụ trong dự án | Lấy từ |
|---|---|---|
| `file://` | `file://data.mount` | Thư mục `files/` cạnh recipe |
| `git://` | `git://github.com/Leminuos/sensornode-ui.git;protocol=https;branch=master` | Git, commit cố định bằng `SRCREV` |

bitbake tìm file `file://` theo danh sách thư mục trong biến `FILESPATH`. Với recipe này, `FILESPATH` gồm (rút gọn):

```
.../sensornode-data/sensornode-data-mount-1.0/sensornode-dev:   ← override theo distro
.../sensornode-data/sensornode-data-mount/sensornode-dev
.../sensornode-data/files/sensornode-dev:
.../sensornode-data/sensornode-data-mount-1.0/bbb-sensornode:   ← override theo machine
.../sensornode-data/sensornode-data-mount/bbb-sensornode:
.../sensornode-data/files/bbb-sensornode
.../sensornode-data/sensornode-data-mount-1.0/arm:              ← override theo kiến trúc
.../sensornode-data/sensornode-data-mount/arm:
.../sensornode-data/files/arm:
.../sensornode-data/files/                                      ← mặc định
```

Nghĩa là ta có thể đặt `files/bbb-sensornode/data.mount` để có bản riêng cho machine đó mà không sửa recipe. Kiểm tra bằng `bitbake -e sensornode-data-mount | grep ^FILESPATH=`.

**`inherit` — dùng lại logic có sẵn.**

`.bbclass` là thư viện dùng chung.

| Class | Thực hiện | Recipe dùng |
|---|---|---|
| `systemd` | Đọc `SYSTEMD_SERVICE`, tạo preset để enable unit trong rootfs | `sensornode-data-mount`, `sensornode-ui`, `ota-confirm-boot`, `journald-persistent` |
| `allarch` | Package không phụ thuộc kiến trúc CPU → build một lần dùng cho mọi machine | `sensornode-data-mount` |
| `deploy` | Thêm task `do_deploy` để đưa artifact ra `deploy/images/` | `sensornode-data-image` |
| `nopackages` | Bỏ các task đóng package: recipe chỉ sinh artifact, không cài gì vào rootfs | `sensornode-data-image` |
| `cmake_qt5` | Configure/compile bằng CMake với Qt5 từ sysroot | `sensornode-ui` |
| `swupdate` | Đóng gói `.swu` từ `sw-description` và image | `sensornode-image-swu` |

**`do_install` — cài file vào thư mục staging `${D}`.** `${D}` không phải rootfs thật mà là `WORKDIR/image/`. Các task sau chia nội dung của `${D}` thành package theo `FILES`.

**`FILES:${PN}`** - package chính gồm những file nào. File cài vào `${D}` mà không thuộc package nào sẽ làm build báo lỗi QA `installed-vs-shipped`.

## 4. Biến và toán tử gán

Mọi toán tử dưới đây đều xuất hiện trong repo:

| Toán tử | Ý nghĩa | Ví dụ trong dự án |
|---|---|---|
| `=` | Gán. `${...}` được mở rộng lúc dùng | `S = "${WORKDIR}/git"` |
| `?=` | Gán nếu chưa ai gán | `SENSORNODE_SLOT_SIZE_MiB ?= "160"` - cho phép `local.conf` ghi đè |
| `:=` | Gán và mở rộng ngay lúc parse | `FILESEXTRAPATHS:prepend := "${THISDIR}/files:"` |
| `+=` / `=+` | Nối sau / trước, có thêm dấu cách | `SRC_URI += " file://…"` |
| `.=` / `=.` | Nối sau / trước, không thêm dấu cách | `BBPATH .= ":${LAYERDIR}"`, `MACHINEOVERRIDES =. "beaglebone-yocto:"` |
| `:append` / `:prepend` | Nối, áp dụng sau cùng, không tự thêm dấu cách | `IMAGE_INSTALL:append = " swupdate …"` |
| `:remove` | Xoá các từ khỏi giá trị cuối cùng | `DISTRO_FEATURES:remove = "x11 wayland …"` |

**Override (`:tên`).** Hậu tố sau dấu `:` chỉ có hiệu lực khi tên đó nằm trong danh sách `OVERRIDES`:

```bitbake
PACKAGECONFIG_DISTRO:pn-qtbase = " linuxfb tslib fontconfig"  # chỉ áp cho recipe qtbase
KMACHINE:bbb-sensornode = "beaglebone"                        # chỉ khi MACHINE = bbb-sensornode
RDEPENDS:${PN} = "qtbase-plugins …"                           # chỉ cho package ${PN}
```

**Python inline `${@...}`.** Biểu thức Python được tính khi mở rộng biến:

```bitbake
SENSORNODE_SLOT_SIZE_KiB = "${@int(d.getVar('SENSORNODE_SLOT_SIZE_MiB')) * 1024}"
IMAGE_FEATURES:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-readonly', 'read-only-rootfs', '', d)}"
```

`d` là datastore của recipe. `bb.utils.contains(var, item, nếu_có, nếu_không, d)` là cách chuẩn để đọc feature flag (chi tiết ở [02-machine-distro-image.md](02-machine-distro-image.md)).

## 5. Task: recipe đi từ source tới package

Recipe không chạy một lệnh `make` duy nhất mà đi qua chuỗi task. Liệt kê task của một recipe:

```bash
bitbake sensornode-data-mount -c listtasks
```

Chuỗi chính cho một recipe thông thường:

```
do_fetch → do_unpack → do_patch → do_prepare_recipe_sysroot → do_configure → do_compile
    → do_install → do_package → do_packagedata → do_package_qa → do_package_write_rpm
    → do_populate_sysroot → do_build
```

| Task | Làm gì | Thư mục liên quan |
|---|---|---|
| `do_fetch` | Tải source theo `SRC_URI` | `DL_DIR` |
| `do_unpack` | Giải nén / checkout vào `WORKDIR` | `S` |
| `do_patch` | Áp các file `.patch` trong `SRC_URI` theo thứ tự | `S` |
| `do_configure` | Chạy bước cấu hình (CMake, Kconfig...) | `B` |
| `do_compile` | Build | `B` |
| `do_install` | Cài vào `${D}` | `D` |
| `do_package*` | Chia `${D}` thành package, kiểm tra QA, ghi `.rpm` | `deploy/rpm/` |
| `do_populate_sysroot` | Chia sẻ header/thư viện cho recipe khác build dựa vào | sysroot |
| `do_deploy` | Đưa artifact ra ngoài | `deploy/images/<machine>/` |

Các thư mục, lấy giá trị thật của `sensornode-ui` ở distro dev:

| Biến | Giá trị |
|---|---|
| `WORKDIR` | `tmp-sensornode-dev/work/cortexa8hf-neon-poky-linux-gnueabi/sensornode-ui/1.0+gitAUTOINC+8a129268da-r0` |
| `S` (source) | `${WORKDIR}/git` - git fetcher checkout vào đây |
| `B` (build) | `${WORKDIR}/build` - class cmake build ngoài source |
| `D` (install) | `${WORKDIR}/image` |

**Thêm task riêng.** [sensornode-data-image.bb](../../meta-sensornode/recipes-core/sensornode-data/sensornode-data-image.bb) khai:

```bitbake
addtask deploy after do_compile before do_build
```

Nghĩa là: `do_deploy` chạy sau khi `mke2fs` tạo xong ext4 ở `do_compile` và phải xong trước `do_build`. Recipe `.swu` làm tương tự với `addtask render_swdesc after do_unpack before do_swuimage`.

**Nối thêm vào task có sẵn.** `do_<task>:append()` chạy thêm lệnh sau task gốc, `:prepend()` chạy trước:

```bitbake
do_compile:append() {
    mkenvimage -s ${SENSORNODE_ENV_SIZE} -o ${B}/u-boot-env.raw ${B}/u-boot-initial-env
}
```

**Phụ thuộc task của các recipe khác nhau:**

```bitbake
do_image_wic[depends] += "virtual/bootloader:do_deploy sensornode-data-image:do_deploy"
```

`[depends]` là một varflag của task: trước khi image chạy `do_image_wic`, bitbake phải chạy xong `do_deploy` của U-Boot và của `sensornode-data-image` vì wic cần các file đó.

## 6. DEPENDS và RDEPENDS

| Biến | Thời điểm | Ví dụ |
|---|---|---|
| `DEPENDS` | Build time: recipe cần header/thư viện/tool của recipe khác để compile | `DEPENDS += "qtbase qtcharts mosquitto"` - app cần header Qt và libmosquitto để link |
| `RDEPENDS:${PN}` | Runtime: package cần package khác có mặt trên board | `RDEPENDS:${PN} = "qtbase-plugins tslib-conf ttf-dejavu-sans"` - app cần plugin linuxfb, file `/etc/ts.conf` và font |

Thư viện được link động (`libQt5Widgets.so`, `libmosquitto.so`) không cần khai `RDEPENDS`: bitbake tự đọc ELF và thêm phụ thuộc. Chỉ khai những thứ ELF không thể hiện được - plugin load lúc runtime, file cấu hình, font.

## 7. File `.bbappend`

Muốn U-Boot của poky có thêm logic A/B mà không sửa file trong `poky/`, dự án viết [meta-sensornode/recipes-bsp/u-boot/u-boot_%.bbappend](../../meta-sensornode/recipes-bsp/u-boot/u-boot_%25.bbappend):

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://0001-bbb-ota.cfg \
    file://0001-bbb-ota-boot-env.patch \
"
```

| Chi tiết | Giải thích |
|---|---|
| Tên file `u-boot_%.bbappend` | Khớp với recipe `u-boot_<version>.bb`. `%` là wildcard cho version - nâng U-Boot lên version khác, bbappend vẫn áp dụng |
| `FILESEXTRAPATHS:prepend := "${THISDIR}/files:"` | Recipe gốc chỉ tìm `file://` trong thư mục của nó (trong `poky/`). Dòng này thêm thư mục `files/` cạnh bbappend vào đầu đường tìm kiếm |
| `SRC_URI:append` | Thêm file cấu hình và patch vào danh sách source của U-Boot |

Nội dung bbappend được ghép vào cuối recipe gốc trước khi parse nên mọi biến và task của recipe gốc đều sửa được.

Quy ước của dự án: bbappend chỉ dùng để sửa recipe thuộc layer khác. Recipe của chính dự án thì sửa thẳng file `.bb`. Logic dùng chung giữa nhiều recipe thì đặt vào file `.inc` rồi `require` như `sensornode-image-common.inc`.

Xem recipe nào đang bị bbappend nào tác động:

```bash
bitbake-layers show-appends | grep -A3 u-boot
```

## 8. Package đi vào image bằng đường nào

Theo chân unit `data.mount` từ repo tới board:

1. `sensornode-data-mount.bb` cài `data.mount` vào `${D}/lib/systemd/system/`.
2. `do_package` đưa file vào package `sensornode-data-mount` (kiểm tra bằng `oe-pkgdata-util list-pkg-files sensornode-data-mount`).
3. `sensornode-image-common.inc` có `IMAGE_INSTALL:append = " sensornode-data-mount …"`.
4. `do_rootfs` của image cài package vào rootfs; class `systemd` enable unit.
5. `do_image_wic` ghi rootfs vào `.wic`.

Chiều ngược lại - một file trên board đến từ package nào:

```bash
oe-pkgdata-util find-path /lib/systemd/system/data.mount
# sensornode-data-mount: /lib/systemd/system/data.mount
```

## 9. sstate và signature

Mỗi task có một signature (hash): nội dung các biến task dùng, nội dung function của task, checksum các file `file://` và signature của các task nó phụ thuộc. Kết quả task được lưu vào `sstate-cache` theo signature.

Lần build sau, nếu signature không đổi, bitbake lấy kết quả từ sstate thay vì chạy lại. Đổi một biến chỉ làm rebuild những task thực sự dùng biến đó, kéo theo các task phụ thuộc.

Hệ quả thực tế:

- Đổi `SENSORNODE_ENV_SIZE` → rebuild U-Boot, libubootenv, image; không rebuild Qt.
- Chỉ thêm dấu cách hay xuống dòng trong giá trị `SRC_URI` cũng làm signature đổi.
- Sửa recipe trong lúc bitbake đang chạy → signature lúc parse khác signature lúc chạy task → lỗi `basehash value changed`.

So sánh vì sao một task bị build lại:

```bash
bitbake sensornode-ui -c do_package -S printdiff
```

## 10. Công cụ điều tra

| Muốn biết | Lệnh |
|---|---|
| Giá trị cuối cùng của một biến trong recipe | `bitbake -e <recipe> \| grep ^TÊN_BIẾN=` |
| Biến đó được gán ở file nào, dòng nào | `bitbake -e <recipe>` rồi tìm khối comment ngay trên dòng `TÊN_BIẾN=` |
| Recipe có những task nào | `bitbake <recipe> -c listtasks` |
| Chạy lại một task | `bitbake <recipe> -c <task> -f` |
| Mở shell với môi trường build của recipe | `bitbake <recipe> -c devshell` |
| Layer đang dùng | `bitbake-layers show-layers` |
| Recipe có trong layer nào, version nào | `bitbake-layers show-recipes '<mẫu>'` |
| bbappend nào áp cho recipe nào | `bitbake-layers show-appends` |
| Package chứa file nào | `oe-pkgdata-util list-pkg-files <package>` |
| File thuộc package nào | `oe-pkgdata-util find-path <đường-dẫn>` |
| Log của một task | `tmp-<distro>/work/<arch>/<recipe>/<ver>/temp/log.do_<task>` |
