# CR-0005: overlay /etc on /data for read-only rootfs

Commit: `e7b611f`

## Vấn đề

Bản production mount rootfs chỉ đọc nhưng chưa có chỗ ghi nào cho `/etc`. Hai hệ quả xảy ra:

- Mọi thao tác ghi vào `/etc` lúc chạy đều lỗi `EROFS`. Ví dụ: file calib cảm ứng `/etc/pointercal` của tslib.
- `/etc/machine-id` là file rỗng do `read_only_rootfs_hook` thuộc class `rootfs-postcommands.bbclass` tạo sẵn và systemd không ghi được vào đó. Kết quả là mỗi lần boot có một machine-id mới và journald tạo thêm một thư mục `/data/journal/<machine-id>/` cho mỗi lần boot.

> [!TIP]
> `/etc` là nơi chứa các cấu hình của hệ thống: fstab, unit systemd, cấu hình mạng, `ts.conf`, `hwrevision`, `sw-versions`...
>
> Phần lớn nội dung này là static, được build một lần và mọi thiết bị đều dùng chung. Tuy nhiên, một số trạng thái riêng của từng thiết bị được sinh ra và thay đổi lúc chạy. Ví dụ như `/etc/machine-id`, `/etc/pointercal`, `/etc/hostname`,...

systemd (PID 1) đọc file `/etc/machine-id` ngay khi khởi động, trước khi bất kỳ unit nào chạy. Vì vậy không thể xử lý bằng một unit bind mount từ `/data`: cần phải được mount trước khi systemd chạy. Các mục còn lại đều có thể đưa sang `/data/config`.

## Thiết kế

Dùng image feature `overlayfs-etc` của poky, bật cùng `read-only-rootfs` khi distro có `sensornode-readonly`.

Class này đổi tên `/sbin/init` thành `/sbin/init.orig` và đặt vào `/sbin/init` một script preinit. Kernel chạy `/sbin/init`, tức là preinit thay vì systemd, script này thực hiện:

1. Mount `/data`.
2. Mount overlay lên `/etc`: lớp lower là `/etc` chỉ đọc của slot, lớp upper là `/data/overlay-etc/upper`.
3. `exec /sbin/init.orig`: chuyển quyền cho systemd và giữ nguyên PID 1.

Khi systemd khởi động, `/etc` đã ghi được. Lần boot đầu, systemd sinh machine-id và lưu vào lớp upper. Những lần boot sau, OTA hay rollback thì đều dùng lại id đó vì upper nằm trên `/data` và hai slot dùng chung.

Các biến cấu hình được đặt trong [`sensornode-image-common.inc`](../../meta-sensornode/recipes-core/images/include/sensornode-image-common.inc). Biến sau là bắt buộc:

```bitbake
OVERLAYFS_ETC_CREATE_MOUNT_DIRS = "0"
```

Với giá trị mặc định `1`, preinit chạy `mount -o remount,rw /` để tạo thư mục mount point, tức là mở rootfs cho ghi và phá hỏng mục đích read-only. Các thư mục `/proc`, `/sys`, `/run`, `/data` đã có sẵn trong rootfs nên không cần bước này.

Giới hạn khi kết hợp với A/B: lớp upper nằm trên /data nên hai slot dùng chung. File nào đã được ghi vào upper sẽ che file cùng tên trong slot mới sau OTA. Vì vậy cấu hình của app vẫn đặt trong `/data/config/`, không dựa vào overlay. Upper chỉ nên chứa những gì hệ thống ghi vào `/etc` (machine-id, `.updated`,...).

## Kiểm chứng trên board

```bash
touch /etc/x && rm /etc/x  # ghi được
cat /etc/machine-id        # ghi lại giá trị
reboot
cat /etc/machine-id        # phải giống giá trị trước reboot
ls /data/journal/          # không sinh thêm thư mục mới sau reboot
find /data/overlay-etc/upper -type f
```

Log boot trên UART có `PREINIT: done; starting </sbin/init>`, không có `PREINIT: Mounting </data> failed!`.

Sau OTA thì `cat /etc/machine-id` vẫn phải ra cùng giá trị.
