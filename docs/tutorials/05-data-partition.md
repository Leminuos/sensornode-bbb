# Phân vùng `/data`

Mọi dữ liệu phải sống sót qua reboot, qua OTA và qua rollback đều nằm trên phân vùng `/data`: file cấu hình user, lịch sử cảm biến, log hệ thống. Tutorial này đi qua toàn bộ vòng đời của phân vùng đó, từ cách recipe tạo ra filesystem lúc build tới unit systemd mount nó lúc boot.

Đọc tài liệu này giúp ta hiểu:

- Vì sao dữ liệu ghi được phải nằm ngoài rootfs.
- Recipe `sensornode-data-image` tạo sẵn filesystem ext4 lúc build bằng `mke2fs -d`.
- Recipe `sensornode-data-mount` và unit `data.mount` tự mount lúc boot.
- Cách wic ghi filesystem đó vào thẻ SD.
- Dữ liệu nào còn, dữ liệu nào mất trong từng tình huống.

## 1. Vì sao cần một phân vùng riêng?

Rootfs không phải chỗ chứa dữ liệu ghi lúc chạy, vì hai ràng buộc sau:

- **OTA ghi đè nguyên slot.** Mỗi lần cập nhật, SWUpdate ghi toàn bộ filesystem mới lên slot không chạy. Thứ gì nằm trong rootfs đều bị thay bằng nội dung của bản build mới.
- **Bản production mount rootfs chỉ đọc.** Mọi thao tác ghi vào rootfs đều trả về lỗi `EROFS`.

Phân vùng `/data` nằm ngoài cả hai slot A/B nên OTA không chạm tới và luôn mount đọc–ghi kể cả trên bản production. Toàn bộ dữ liệu cần tồn tại lâu dài đều nằm ở đây:

| Dữ liệu | Đường dẫn |
|---|---|
| Cấu hình broker MQTT | `/data/config/mqtt.json` |
| Tuỳ chọn OTA (auto/manual, URL manifest) | `/data/config/ota.json` |
| Tuỳ chọn giao diện (độ sáng màn hình) | `/data/config/setting.json` |
| Lịch sử số liệu cảm biến | `/data/logs/sensors.csv` |
| Log hệ thống | `/data/journal/` |

Bảng tra ý nghĩa từng file JSON: [references/runtime-config.md](../references/runtime-config.md).

Vị trí và kích thước trong layout thẻ SD: [references/partition-layout.md](../references/partition-layout.md).

## 2. Thành phần

| Mảnh | File | Nhiệm vụ |
|---|---|---|
| Nội dung filesystem | [sensornode-data-image.bb](../../meta-sensornode/recipes-core/sensornode-data/sensornode-data-image.bb) | Tạo file `sensornode-data.ext4` có sẵn cấu hình mặc định |
| Unit mount | [sensornode-data-mount.bb](../../meta-sensornode/recipes-core/sensornode-data/sensornode-data-mount.bb) + [data.mount](../../meta-sensornode/recipes-core/sensornode-data/files/data.mount) | Cài unit vào rootfs và systemd mount `/data` lúc boot |
| Vị trí trên thẻ | [bbb-sensornode-ab.wks.in](../../meta-sensornode/wic/bbb-sensornode-ab.wks.in) | wic ghi file ext4 vào phân vùng thứ ba |

## 3. Recipe `sensornode-data-image`

### 3.1. Toàn bộ recipe

```bitbake
SUMMARY = "Pre-populated ext4 image for the /data partition"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://mqtt.json    \
    file://ota.json     \
    file://setting.json \
"

S = "${WORKDIR}"

DEPENDS = "e2fsprogs-native"

inherit deploy nopackages

do_compile[cleandirs] = "${WORKDIR}/data-root"

do_compile() {
    install -d ${WORKDIR}/data-root/journal

    install -d ${WORKDIR}/data-root/config
    install -m 0644 ${WORKDIR}/mqtt.json    ${WORKDIR}/data-root/config/mqtt.json
    install -m 0644 ${WORKDIR}/ota.json     ${WORKDIR}/data-root/config/ota.json
    install -m 0644 ${WORKDIR}/setting.json ${WORKDIR}/data-root/config/setting.json

    mke2fs -t ext4 -L data \
           -d ${WORKDIR}/data-root \
           ${WORKDIR}/${SENSORNODE_DATA_IMG} \
           ${SENSORNODE_DATA_SIZE_KiB}
}

do_deploy() {
    install -Dm 0644 ${WORKDIR}/${SENSORNODE_DATA_IMG} ${DEPLOYDIR}/${SENSORNODE_DATA_IMG}
}

addtask deploy after do_compile before do_build
```

### 3.2. Giải thích từng khối

| Khối | Ý nghĩa |
|---|---|
| `SRC_URI` | Ba file JSON mặc định nằm trong folder `files/` cạnh recipe. Đây là nội dung xuất xưởng của `/data/config/` |
| `DEPENDS = "e2fsprogs-native"` | Cần tool `mke2fs` để tạo phân vùng `/data`. Hậu tố `-native` là bản build cho host |
| `inherit deploy` | Thêm task `do_deploy` để đưa artifact ra `deploy/images/<machine>/` |
| `inherit nopackages` | Recipe chỉ tạo artifact cho wic, không cài gì vào rootfs. Class này bỏ toàn bộ các task đóng gói (`do_package`, `do_package_write_rpm`...) nên không sinh package rỗng và build nhanh hơn |
| `do_compile[cleandirs]` | Xoá sạch `data-root/` trước mỗi lần `do_compile`, tránh lẫn file từ lần build trước khi đổi nội dung `SRC_URI` |
| `addtask deploy after do_compile before do_build` | Đặt `do_deploy` vào đúng chỗ trong chuỗi task: sau khi có file ext4, trước khi recipe done |

### 3.3. Tool `mke2fs`

```bash
mke2fs -t ext4 -L data -d <thư-mục-nguồn> <file-đích> <số-block>
```

| Tham số | Ý nghĩa |
|---|---|
| `-t ext4` | Loại filesystem |
| `-L data` | Ghi nhãn `data` vào superblock. Unit mount tìm phân vùng theo nhãn này |
| `-d <thư-mục>` | Đóng gói toàn bộ nội dung thư mục vào filesystem mới |
| `<số-block>` | Kích thước tính theo block 1 KiB. `SENSORNODE_DATA_SIZE_KiB` = 131072 → 128 MiB, bằng đúng `--fixed-size` của phân vùng trong wks |

Điểm mạnh của `-d`: không cần quyền root, không cần mount, không cần loop device. Đây là cách chuẩn để tạo filesystem có sẵn nội dung trong Yocto.

Kích thước và tên file đều lấy từ [sensornode-vars.inc](../../meta-sensornode/conf/include/sensornode-vars.inc) nên wks và recipe luôn đồng bộ.

### 3.4. Kiểm tra artifact trên máy build

```bash
D=tmp-sensornode-dev/deploy/images/bbb-sensornode

debugfs -R "ls -l /config" $D/sensornode-data.ext4
debugfs -R "stats" $D/sensornode-data.ext4 | grep -E "volume name|Block count|Block size"
# Filesystem volume name:   data
# Block count:              131072
# Block size:               1024
```

## 4. Đưa filesystem lên thẻ SD

Dòng tương ứng trong wks:

```
part /data --source rawcopy --ondisk mmcblk0 --fstype=ext4 --align 4096 --fixed-size ${SENSORNODE_DATA_SIZE_MiB} --sourceparams="file=${SENSORNODE_DATA_IMG}"
```

| Option | Ý nghĩa |
|---|---|
| `--source rawcopy` | Copy nguyên file `SENSORNODE_DATA_IMG`, không tạo filesystem mới |
| `--fstype=ext4` | Quyết định partition type trong MBR (`83` = Linux). Bỏ đi thì wic mặc định coi là FAT, kernel dò sai kiểu và `/data` không mount được |
| `--fixed-size` | Kích thước phân vùng phải bằng `SENSORNODE_DATA_SIZE_MiB` |
| `--align 4096` | Căn chỉnh 4 MiB |

Không dùng `--label` ở đây: với `rawcopy` thì wic sẽ gọi thêm công cụ gán nhãn sau khi copy, điều này rất dễ lỗi. Nhãn đã có sẵn trong superblock nhờ `mke2fs -L data`.

Image cần khai báo phụ thuộc để file ext4 chắc chắn có trước khi wic chạy:

```bitbake
do_image_wic[depends] += "virtual/bootloader:do_deploy sensornode-data-image:do_deploy"
```

## 5. Unit `data.mount`

### 5.1. Recipe

```bitbake
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

| Dòng | Ý nghĩa |
|---|---|
| `inherit systemd` | Cho phép khai báo `SYSTEMD_SERVICE` và tự tạo preset enable unit trong rootfs |
| `inherit allarch` | Nội dung chỉ là file text, không phụ thuộc kiến trúc CPU → package `noarch`, build một lần dùng cho mọi machine |
| `SYSTEMD_AUTO_ENABLE = "enable"` | Unit được enable sẵn trong image, không cần chạy `systemctl enable` trên board |

Recipe được image cài qua `IMAGE_INSTALL` trong [sensornode-image-common.inc](../../meta-sensornode/recipes-core/images/include/sensornode-image-common.inc):

```bitbake
IMAGE_INSTALL:append = " sensornode-data-mount journald-persistent"
```

### 5.2. Nội dung unit

```ini
[Unit]
Description=Data Partition
DefaultDependencies=no
After=local-fs-pre.target
Before=local-fs.target

[Mount]
What=LABEL=data
Where=/data
Type=ext4
Options=defaults,noatime

[Install]
WantedBy=local-fs.target
```

| Dòng | Ý nghĩa |
|---|---|
| Tên file `data.mount` | systemd bắt buộc tên unit match đường dẫn mount: `/data` → `data.mount`, `/var/lib/x` → `var-lib-x.mount`. Đặt sai tên thì unit không bao giờ được dùng |
| `DefaultDependencies=no` | Bỏ các phụ thuộc mặc định mà systemd tự thêm để unit chạy được ở giai đoạn rất sớm của boot |
| `After=local-fs-pre.target`, `Before=local-fs.target` | Mount cùng nhóm với các filesystem cục bộ khác và hoàn tất trước khi dịch vụ thường khởi động |
| `What=LABEL=data` | Tìm thiết bị theo nhãn thay vì `/dev/mmcblk0p3`. Nhãn cố định, không phụ thuộc thứ tự phân vùng hay layout đổi về sau |
| `Options=defaults,noatime` | `noatime`: đọc file không ghi lại thời điểm truy cập, giảm bớt ghi thừa lên thẻ nhớ |
| `WantedBy=local-fs.target` | Khi enable, unit được kéo vào mỗi lần boot |

### 5.3. Điểm mount trong rootfs

Rootfs phải có sẵn thư mục `/data` rỗng để mount đè lên. Image tạo nó sau khi dựng rootfs:

```bitbake
create_data_mountpoint() {
    install -d -m 0755 ${IMAGE_ROOTFS}/data
}
ROOTFS_POSTPROCESS_COMMAND += "create_data_mountpoint; "
```

### 5.4. Service phụ thuộc `/data`

Service nào cần `/data` phải tự khai báo nếu không nó có thể chạy trước lúc mount và ghi nhầm vào thư mục rỗng trên rootfs:

| Khai báo | Ý nghĩa |
|---|---|
| `After=data.mount` | Chỉ chạy sau khi mount xong |
| `Requires=data.mount` | Thêm điều kiện: mount thất bại thì service không chạy |

## 6. Kiểm tra trên board

```bash
findmnt /data
# TARGET SOURCE         FSTYPE OPTIONS
# /data  /dev/mmcblk0p3 ext4   rw,noatime

systemctl status data.mount
lsblk -o NAME,LABEL,SIZE,MOUNTPOINT
ls /data/config
touch /data/test && rm /data/test     # phải ghi được kể cả trên bản production
```

Nếu `/data` không mount:

| Kiểm tra | Lệnh |
|---|---|
| Unit có được enable không | `systemctl is-enabled data.mount` |
| Nhãn phân vùng có đúng không | `blkid /dev/mmcblk0p3` → phải thấy `LABEL="data"` |
| Có lỗi filesystem không | `journalctl -b \| grep -i "data\|ext4"` |
| Phân vùng có đúng kiểu không | `fdisk -l /dev/mmcblk0` → type `83 Linux` |


