# Read-only rootfs

Bản production mount rootfs ở chế độ chỉ đọc. Tutorial này giải thích vì sao, kernel và systemd làm việc đó ra sao, Yocto thay đổi những gì khi bật `read-only-rootfs` và các chương trình vẫn chạy được nhờ đâu khi không ghi được vào `/`.

Đọc tài liệu này giúp ta hiểu:

- Lợi ích và cái giá của rootfs chỉ đọc.
- Hai nơi quyết định `/` là `ro` hay `rw`: kernel command line và `/etc/fstab`.
- Image feature `read-only-rootfs` sửa rootfs lúc build như thế nào.
- Overlay `/etc` trên `/data` để `/etc` ghi được.
- Ba cơ chế cho dữ liệu cần ghi: tmpfs, volatile bind, phân vùng `/data`.
- Cách tìm chương trình đang cố ghi vào rootfs.

## 1. Vì sao cần rootfs chỉ đọc?

| Lợi ích | Giải thích |
|---|---|
| Chống hỏng filesystem khi mất điện | Không có thao tác ghi nào trên slot đang chạy thì không có gì để hỏng. |
| Tương tác với mô hình A/B | Slot phải giống hệt lúc flash để rollback an toàn. Nếu runtime ghi lung tung vào slot A thì khi quay về slot A không còn là quay về một bản đã biết - mất tính tái lập |

Đánh đổi: Mọi thứ cần ghi phải có chỗ khác để ghi.

## 2. Ai quyết định rootfs là `ro` hay `rw`

**Bước 1: kernel mount rootfs lần đầu.**

Theo tham số `ro` trên kernel command line do U-Boot truyền. Script `ota_boot` trong U-Boot env của dự án đặt:

```
setenv bootargs root=/dev/mmcblk0p${mmc_part} ro rootwait console=ttyO0,115200n8 panic=10
```

**Bước 2: systemd remount theo fstab.**

Unit `systemd-remount-fs.service` đọc dòng của `/` trong `/etc/fstab` và remount với option ở đó:

| Distro | Dòng `/` trong `/etc/fstab` | Kết quả khi chạy |
|---|---|---|
| `sensornode-dev` | `/dev/root  /  auto  defaults  1  1` | `defaults` gồm `rw` → systemd remount `rw` |
| `sensornode` | `/dev/root  /  auto  ro  1  0` | Giữ `ro` |

Chỉ đặt `ro` trong bootargs là chưa đủ: không sửa fstab thì systemd vẫn remount `rw`.

## 3. Bật feature trong dự án

Distro production bật `sensornode-readonly`, image dịch sang image feature của poky:

```bitbake
IMAGE_FEATURES:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-readonly', \
    'read-only-rootfs overlayfs-etc', '', d)}"
```

`overlayfs-etc` cho phép ghi vào `/etc`.

## 4. `read-only-rootfs` làm gì lúc build

Khi image có feature này, poky chạy hàm `read_only_rootfs_hook` (trong `poky/meta/classes/rootfs-postcommands.bbclass`) sau khi `do_rootfs`:

| Công việc | Chi tiết |
|---|---|
| Sửa fstab | Đổi dòng của `/` từ `defaults` sang `ro`, cột fsck-pass đổi thành `0` |
| SSH host key | Mỗi máy cần bộ khóa SSH riêng, bình thường được tạo và lưu vào `/etc/ssh`. Vì `/etc` đã khóa, nên nó cấu hình sshd tạo key trong RAM (`/var/run/ssh`). Hệ quả: key đổi mỗi lần boot. Nếu muốn khóa cố định thì lưu sang `/data`. **Bản production không có SSH nên không áp dụng** |

Cả hai distro đều có file `/etc/machine-id` rỗng. Lần boot đầu, systemd sinh machine-id rồi ghi vào `/etc/machine-id` và giá trị này cố định từ đó. Bản dev ghi được vì rootfs là `rw`. Bản production ghi được nhờ overlay `/etc`. Nếu không có overlay, systemd sẽ sinh một machine-id tạm mới mỗi lần boot, và journald tạo thêm một thư mục `/data/journal/<machine-id>/` cho mỗi lần boot.

Ngoài ra, `read_only_rootfs_hook` có thêm `APPEND:append = " ro"` để nối `ro` vào kernel cmdline. Nhưng trong dự án, kernel cmdline không lấy từ biến `APPEND` mà nó được script `ota_boot` tự setenv bootargs trong U-Boot env. Nên `APPEND:append` không tới được cmdline thật.
