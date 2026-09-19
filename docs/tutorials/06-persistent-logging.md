# Log hệ thống persistent trên `/data`

Mặc định, log của systemd trên image Yocto nằm trong RAM và mất sạch sau mỗi lần tắt nguồn. Nếu đúng lúc cần đọc lại để điều tra sự cố thì không còn gì. Tutorial này trình bày cách dự án đưa journal sang phân vùng `/data`: cấu hình journald, rule tạo thư mục và một service riêng để xử lý vấn đề thứ tự lúc boot.

Đọc tài liệu này giúp ta hiểu:

- Journal mặc định nằm ở đâu và vì sao mất khi reboot.
- Recipe `journald-persistent` cài những gì và mỗi file làm gì.
- Vì sao chỉ đổi `Storage=persistent` là chưa đủ.
- Cấu hình xoay vòng log để không lấp đầy phân vùng 128 MiB.
- Cách đọc log của những lần boot trước và các hạn chế đang có.

## 1. Vấn đề

systemd-journald ghi log vào một trong hai nơi:

| Nơi lưu | Đường dẫn | Tính chất |
|---|---|---|
| Runtime (volatile) | `/run/log/journal/` | tmpfs trong RAM, mất khi tắt nguồn |
| Persistent | `/var/log/journal/` | Chỉ dùng khi thư mục này tồn tại và ghi được |

Rootfs không phải chỗ để ghi: bản production mount chỉ đọc và ghi vào slot đang chạy sẽ phá tính tái lập của mô hình A/B. Nơi duy nhất ghi được lâu dài là `/data`.

Dự án dùng luôn journald thay vì viết cơ chế log riêng trong ứng dụng: journald đã có sẵn phân loại theo mức ưu tiên, theo unit, theo lần boot, có rotate và có công cụ đọc (`journalctl`).

## 2. Recipe `journald-persistent`

### 2.1. Toàn bộ recipe

```bitbake
SUMMARY = "Save persistent journald on /data with rotation"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://10-persistent.conf \
    file://journald-data.conf \
    file://journald-data-flush.service \
"

S = "${WORKDIR}"

inherit systemd

RDEPENDS:${PN} = "systemd"

SYSTEMD_SERVICE:${PN} = "journald-data-flush.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sysconfdir}/systemd/journald.conf.d
    install -m 0644 ${WORKDIR}/10-persistent.conf \
        ${D}${sysconfdir}/systemd/journald.conf.d/10-persistent.conf

    install -d ${D}${sysconfdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/journald-data.conf \
        ${D}${sysconfdir}/tmpfiles.d/journald-data.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/journald-data-flush.service \
        ${D}${systemd_system_unitdir}/journald-data-flush.service
}

FILES:${PN} = " \
    ${sysconfdir}/systemd/journald.conf.d/10-persistent.conf \
    ${sysconfdir}/tmpfiles.d/journald-data.conf \
    ${systemd_system_unitdir}/journald-data-flush.service \
"
```

### 2.2. Nhiệm vụ mỗi file

| File | Đường dẫn trên rootfs | Nhiệm vụ |
|---|---|---|
| `10-persistent.conf` | `/etc/systemd/journald.conf.d/` | Bảo journald ghi persistent và giới hạn dung lượng |
| `journald-data.conf` | `/etc/tmpfiles.d/` | Tạo `/data/journal` với quyền đúng |
| `journald-data-flush.service` | `/lib/systemd/system/` | Trỏ `/var/log/journal` sang `/data/journal` đúng thời điểm rồi chuyển log sang đó |

Dùng thư mục `journald.conf.d/` thay vì sửa thẳng `/etc/systemd/journald.conf`: cấu hình của dự án tách riêng, không xung đột khi nâng cấp systemd. Tiền tố `10-` quyết định thứ tự đọc khi có nhiều file.

## 3. Cấu hình journald

```ini
[Journal]
Storage=persistent
SyncIntervalSec=300

SystemMaxUse=20M
SystemKeepFree=15M
SystemMaxFileSize=4M
SystemMaxFiles=5
MaxRetentionSec=1month
MaxFileSec=1week
```

| Tuỳ chọn | Ý nghĩa | Lý do |
|---|---|---|
| `Storage=persistent` | Ghi log vào `/var/log/journal`, tự tạo thư mục nếu chưa có | Bật chế độ lưu persistent |
| `SyncIntervalSec=300` | 5 phút mới đồng bộ xuống disk một lần | Giảm số lần ghi lên thẻ nhớ. Level log `CRIT` trở lên vẫn được đồng bộ ngay nên sự cố nặng không bị mất |
| `SystemMaxUse=20M` | Tổng dung lượng journal tối đa | `/data` chỉ 128 MiB và còn phải chứa cấu hình lẫn dữ liệu cảm biến |
| `SystemKeepFree=15M` | Luôn chừa trống `15M` dung lượng | Bảo vệ phần còn lại của `/data` khỏi bị log lấp đầy |
| `SystemMaxFileSize=4M` | Kích thước tối đa một file journal | File nhỏ thì rotate mịn hơn và mất ít log hơn mỗi lần xoá |
| `SystemMaxFiles=5` | Số file tối đa giữ lại | Giới hạn thứ hai bên cạnh dung lượng |
| `MaxRetentionSec=1month` | Xoá log cũ hơn một tháng | Dữ liệu quá cũ không còn giá trị |
| `MaxFileSec=1week` | Đóng file hiện tại và mở file mới sau một tuần | Bảo đảm file được rotate cả khi thiết bị ghi rất ít log |

journald tự thực hiện toàn bộ việc rotate theo các ngưỡng này, không cần `logrotate`.

## 4. Quyền thư mục

```
d /data/journal 2755 root systemd-journal -
```

| Cột | Giá trị | Ý nghĩa |
|---|---|---|
| Kiểu | `d` | Tạo thư mục nếu chưa có |
| Đường dẫn | `/data/journal` | Nơi chứa journal |
| Quyền | `2755` | `755` cộng bit setgid |
| Chủ sở hữu | `root` | |
| Nhóm | `systemd-journal` | Nhóm mà journald chạy, cần quyền ghi |
| Tuổi | `-` | Không tự xoá file theo thời gian, việc xoá do journald lo |

`systemd-tmpfiles` đọc các file trong `/etc/tmpfiles.d/` lúc boot. Thư mục `/data/journal` cũng đã được tạo sẵn trong filesystem lúc build nên rule này chủ yếu bảo đảm quyền đúng và xử lý trường hợp thư mục bị xoá.

## 5. Vấn đề thứ tự lúc boot và service `journald-data-flush`

### 5.1. Vì sao `Storage=persistent` là chưa đủ

Chuỗi sự kiện lúc boot:

1. systemd khởi động journald và log ban đầu ghi vào `/run/log/journal` (RAM).
2. `systemd-journal-flush.service` chạy rất sớm. Nó có nhiệm vụ chuyển log từ `/run` sang `/var/log/journal`. Nhưng lúc này `/data` chưa được mount và `/var/log/journal` chưa trỏ đi đâu cả.
3. Không có thư mục persistent, journald tiếp tục ghi vào RAM cho đến hết phiên và không tự chuyển lại sau đó.
4. `/data` mount ở bước sau, nhưng đã muộn.

Thêm nữa, `/var/log` nằm trên tmpfs nên symlink `/var/log/journal → /data/journal` không thể tạo sẵn lúc build: mỗi lần boot tmpfs lại rỗng.

### 5.2. Service xử lý

```ini
[Unit]
Description=Redirect and flush systemd journal to /data
After=data.mount
Requires=data.mount

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/mkdir -p /data/journal
ExecStart=/bin/ln -sfn /data/journal /var/log/journal
ExecStart=/bin/journalctl --flush

[Install]
WantedBy=multi-user.target
```

| Dòng | Ý nghĩa |
|---|---|
| `After=data.mount` | Chỉ chạy sau khi `/data` đã mount |
| `Requires=data.mount` | Mount thất bại thì service không chạy, tránh tạo symlink trỏ vào thư mục rỗng trên rootfs |
| `Type=oneshot` + `RemainAfterExit=yes` | Chạy một lần rồi kết thúc nhưng systemd vẫn coi là active để các unit khác phụ thuộc được |
| `mkdir -p /data/journal` | Phòng trường hợp thư mục bị xoá |
| `ln -sfn /data/journal /var/log/journal` | Tạo lại symlink trên tmpfs |
| `journalctl --flush` | Yêu cầu journald chuyển toàn bộ log đang ở `/run` sang persistent và ghi tiếp vào đó |

Thứ tự ba lệnh `ExecStart` là quan trọng: có thư mục → có symlink → mới yêu cầu flush.

## 6. Kiểm tra trên board

```bash
# Service đã chạy chưa
systemctl status journald-data-flush

# Symlink đã trỏ đúng chưa
ls -l /var/log/journal
# /var/log/journal -> /data/journal

# Journal đang nằm ở đâu, chiếm bao nhiêu
journalctl --disk-usage
ls /data/journal/

# /run còn giữ log không (sau khi flush thì gần như rỗng)
ls /run/log/journal/ 2>/dev/null
```

Kiểm tra tính persisstent: ghi một dấu mốc, reboot, rồi tìm lại:

```bash
logger -p warning "MOC-KIEM-TRA-PERSISTENT"
reboot
# sau khi boot lại
journalctl -b -1 | grep MOC-KIEM-TRA-PERSISTENT
```

Các lệnh đọc log thường dùng:

| Mục đích | Lệnh |
|---|---|
| Log lần boot trước | `journalctl -b -1` |
| Chỉ cảnh báo trở lên | `journalctl -p warning` |
| Theo một unit | `journalctl -u sensornode-ui` |
| Theo dõi trực tiếp | `journalctl -f` |
| Liệt kê các lần boot đã lưu | `journalctl --list-boots` |
| Đọc từ mọi thư mục journal | `journalctl -m` |
| Đọc một thư mục cụ thể | `journalctl -D /data/journal/<machine-id>` |
