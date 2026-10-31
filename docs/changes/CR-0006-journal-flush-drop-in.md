# CR-0006: redirect journal to /data from systemd-journal-flush

Commit: `3c1479c`

## Hành vi hiện tại

journald ghi log vào RAM (`/run/log/journal`) trước. Sau đó, unit chuẩn `systemd-journal-flush.service` chạy `journalctl --flush` để chuyển log sang `/var/log/journal`.

Tuy nhiên, `/var/log` là symlink trỏ tới `var/volatile/log` mà `/var/volatile` là tmpfs khai trong `/etc/fstab`.

Nghĩa là, mặc định cả `/run/log/journal` lẫn `/var/log/journal` đều nằm trong RAM. Muốn log được giữ lại sau khi tắt nguồn thì mỗi lần boot phải tạo symlink `/var/log/journal -> /data/journal`.

Trước đây, việc này do service riêng `journald-data-flush.service` làm:

```ini
[Unit]
Description=Redirect and flush systemd journal to /data
After=data.mount
Requires=data.mount
...
[Install]
WantedBy=multi-user.target
```

Tuy nhiên, trình tự lúc boot như sau:
1. `systemd-journal-flush.service` chạy sớm trong `sysinit.target`. Lúc này chưa có symlink nên flush không có tác dụng, log vẫn ở RAM.
2. Toàn bộ log của giai đoạn `sysinit.target` và `basic.target` tiếp tục nằm trong RAM.
3. Chỉ khi tới `multi-user.target`, `journald-data-flush.service` mới tạo symlink và flush log sang `/data`.

→ Tức là, phần log ở giai đoạn boot sớm không được lưu vào `/data`. Khi mất điện đột ngột hoặc khi hệ thống treo trước lúc `/data` mount thì log sẽ bị mất. Đây lại chính là phần log cần nhất khi điều tra lỗi boot.

## Hành vi mới

Bỏ service `journald-data-flush.service`. Thay vào đó, recipe `journald-persistent` cài thêm một drop-in cho unit chuẩn tại `/lib/systemd/system/systemd-journal-flush.service.d/10-journal-on-data.conf`:

```ini
[Unit]
RequiresMountsFor=/data /var/volatile/log

[Service]
ExecStartPre=/bin/mkdir -p /data/journal /var/volatile/log
ExecStartPre=/bin/ln -sfn /data/journal /var/log/journal
```

Unit chuẩn giờ làm cả ba việc, theo thứ tự:

1. Chờ `/data` và `/var/volatile` mount xong (`RequiresMountsFor`).
2. Tạo thư mục và symlink (`ExecStartPre`).
3. Chuyển log sang `/data` bằng `ExecStart=journalctl --flush` có sẵn.

> [!NOTE]
> Drop-in là cơ chế của systemd cho phép sửa hoặc bổ sung một unit có sẵn mà không phải chép lại toàn bộ file unit. Nó là file `.conf` đặt trong thư mục `<unit>.d/`:
>
> ```
> /lib/systemd/system/systemd-journal-flush.service                           ← unit gốc của systemd
> /lib/systemd/system/systemd-journal-flush.service.d/10-journal-on-data.conf ← drop-in của dự án
> ```
>
> Khi nạp unit, systemd đọc file gốc trước, sau đó áp lần lượt các drop-in theo thứ tự tên file (tiền tố 10- dùng để sắp thứ tự).
>
> Với các directive kiểu danh sách như `RequiresMountsFor=` hay `ExecStartPre=`, giá trị được cộng thêm vào unit gốc chứ không thay thế. 
>
> systemd tìm drop-in ở nhiều thư mục, theo thứ tự ưu tiên giảm dần:
> | Thư mục | Dùng cho |
> | --- | --- |
> | `/etc/systemd/system/<unit>.d/` | Quản trị viên sửa trên máy |
> | `/run/systemd/system/<unit>.d/` | Thay đổi tạm, mất khi reboot |
> | `/lib/systemd/system/<unit>.d/` | 	Gói phần mềm cài vào (vendor) |
>
> Xem unit sau khi gộp bằng `systemctl cat systemd-journal-flush.service`.

## Kiểm chứng

### Trên máy build

Build image production:

```bash
DISTRO=sensornode BB_ENV_PASSTHROUGH_ADDITIONS="$BB_ENV_PASSTHROUGH_ADDITIONS DISTRO" bitbake sensornode-image
```

Kiểm tra rootfs có drop-in và không còn service cũ:

```bash
zcat tmp-sensornode/deploy/images/bbb-sensornode/sensornode-image-bbb-sensornode.ext4.gz > prod.ext4
debugfs -R "cat /lib/systemd/system/systemd-journal-flush.service.d/10-journal-on-data.conf" prod.ext4
debugfs -R "stat /lib/systemd/system/journald-data-flush.service" prod.ext4
```

```
[Unit]
RequiresMountsFor=/data /var/volatile/log

[Service]
ExecStartPre=/bin/mkdir -p /data/journal /var/volatile/log
ExecStartPre=/bin/ln -sfn /data/journal /var/log/journal
/lib/systemd/system/journald-data-flush.service: File not found by ext2_lookup
```

→ Drop-in có trong rootfs, service cũ đã bị xoá.

### Trên board

Kiểm tra drop-in đã được áp và unit chạy thành công:

```bash
systemctl cat systemd-journal-flush.service  | grep 10-journal-on-data.conf
systemctl status systemd-journal-flush.service   # active (exited)
ls -l /var/log/journal                           # -> /data/journal
```

Kiểm tra thứ tự: unit phải chạy sau hai mount và xong trước `sysinit.target`:

```
systemctl show -p After -p Requires systemd-journal-flush.service   # có data.mount và var-volatile.mount
systemd-analyze critical-chain systemd-journal-flush.service
```

Kiểm tra log còn lại sau reboot:

```bash
logger -p warning "check-persistent"
reboot
journalctl -b -1 | grep "check-persistent"
```
