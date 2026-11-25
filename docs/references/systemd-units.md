# Systemd units lúc boot

Bảng tra các unit xuất hiện trong SensorNode: unit là gì, làm nhiệm vụ gì và liên quan thế nào tới dự án.

## 1. Các loại unit

Phần đuôi tên unit cho biết loại của nó:

| Đuôi | Loại | Ý nghĩa | Ví dụ |
|---|---|---|---|
| `.target` | Mốc | Nhóm các unit lại thành một mốc để các unit khác xếp thứ tự theo. | `sysinit.target` |
| `.service` | Process | Một chương trình hoặc script do systemd khởi động và theo dõi | `systemd-udevd.service` |
| `.mount` | Mount point | Một filesystem được mount. Tên unit là đường dẫn, dấu `/` thay bằng `-` | `var-lib.mount` = `/var/lib` |
| `.device` | Thiết bị | Một thiết bị kernel mà udev đã xử lý xong. systemd tạo unit này tự động, không ai viết file cho nó | `dev-mmcblk0p5.device` |
| `.socket` | Socket | systemd mở socket trước, khi có kết nối thì mới khởi động service tương ứng (socket activation) | `sshd.socket` |
| `.path` | Theo dõi file | Khởi động service khi một file hoặc thư mục thay đổi | `systemd-ask-password-wall.path` |
| `.timer` | Hẹn giờ | Khởi động service theo lịch, giống cron | `systemd-tmpfiles-clean.timer` |
| `.slice` | Nhóm cgroup | Nhóm tiến trình để chia tài nguyên (CPU, RAM) | `system.slice` |
| `.scope` | Nhóm cgroup | Giống slice nhưng chứa tiến trình không do systemd khởi động | `init.scope` |

Ký tự lạ trong tên unit là ký tự đã được escape: `\x2d` là `-`, `\x40` là `@`. Unit có `@` là template: `modprobe@drm.service` là template `modprobe@.service` chạy với tham số `drm`.

## 2. Các giai đoạn boot

```
kernel
  │
  ▼
systemd (PID 1) khởi tạo
  │
  ▼
Early boot ──────────────► sysinit.target
            mount filesystem, udev, journald, tmpfiles,...
  │
  ▼
sockets.target + timers.target + paths.target ──► basic.target
  │
  ▼
Service thường: dbus, mạng, UI, daemon của dự án ──► multi-user.target
```

Phần lớn service khai báo `DefaultDependencies=yes` (mặc định), nghĩa là ngầm có `After=basic.target`. Vì vậy mọi thứ chạy trước `sysinit.target` đều làm chậm tất cả daemon của dự án.

## 3. Target

| Unit | Ý nghĩa |
|---|---|
| `local-fs-pre.target` | Điểm ngay trước khi mount filesystem local. Các unit cần chạy trước mount thì phải `Before=` target này |
| `local-fs.target` | Mọi filesystem local trong fstab đã mount xong |
| `remote-fs.target` | Mọi filesystem mạng (NFS,...) đã mount xong |
| `swap.target` | Mọi swap đã bật |
| `slices.target` | Các slice cơ bản đã được tạo |
| `paths.target`, `timers.target`, `sockets.target` | Mọi unit `.path`, `.timer`, `.socket` đã sẵn sàng |
| `network-pre.target` | Điểm trước khi cấu hình mạng, dùng cho firewall |
| `time-set.target` | Đồng hồ hệ thống đã được đặt từ nguồn local (RTC hoặc mốc thời gian timesyncd lưu lại), chưa chắc đã đồng bộ NTP |
| `sysinit.target` | Kết thúc early boot. Từ đây service thường mới được phép chạy |
| `basic.target` | Hệ thống cơ bản sẵn sàng: sysinit + sockets + timers + paths + slices |
| `network.target` | Dịch vụ quản lý mạng đã chạy. Không có nghĩa là đã có IP |
| `nss-lookup.target` | Dịch vụ phân giải tên (resolved) đã chạy |
| `getty.target` | Các màn hình đăng nhập console đã chạy |
| `usb-gadget.target` | Có cổng USB device (UDC). Dùng để khởi động dịch vụ USB gadget (nếu có) |
| `multi-user.target` | Mốc đích của boot: hệ thống chạy đầy đủ, không có giao diện đồ hoạ X/Wayland |

## 4. Slice và scope (nhóm cgroup)

| Unit | Nhiệm vụ |
|---|---|
| `-.slice` | Gốc của cây cgroup |
| `system.slice` | Chứa mọi service hệ thống, kể cả daemon của dự án |
| `user.slice` | Chứa phiên đăng nhập của người dùng (SSH, console) |
| `system-getty.slice`, `system-serial\x2dgetty.slice` | Chứa các tiến trình đăng nhập console |
| `system-modprobe.slice` | Chứa các instance `modprobe@*.service` |
| `system-systemd\x2dbacklight.slice` | Chứa các instance `systemd-backlight@*.service` |
| `init.scope` | Chứa chính systemd (PID 1) |

Các unit này chỉ tạo nhóm, không tốn thời gian boot đáng kể.

## 5. Socket và path

| Unit | Nhiệm vụ |
|---|---|
| `systemd-journald.socket` | Socket nhận log gửi bằng API journal |
| `systemd-journald-dev-log.socket` | `/dev/log`, nhận log kiểu syslog truyền thống |
| `systemd-initctl.socket` | `/dev/initctl`, tương thích lệnh của SysV init cũ |
| `systemd-udevd-control.socket` | Kênh điều khiển udevd, dùng bởi `udevadm` |
| `systemd-udevd-kernel.socket` | Netlink nhận sự kiện thiết bị (uevent) từ kernel |
| `systemd-networkd.socket` | Netlink để networkd nhận thay đổi về interface mạng |
| `systemd-userdbd.socket` | Dịch vụ tra cứu user/group mở rộng. Dự án không dùng |
| `dbus.socket` | Socket của D-Bus system bus, D-Bus chỉ khởi động khi có tiến trình cần |
| `sshd.socket` | Lắng nghe port 22. Có kết nối thì systemd mới khởi động một tiến trình sshd riêng cho kết nối đó. |
| `systemd-ask-password-console.path`, `systemd-ask-password-wall.path` | Theo dõi `/run/systemd/ask-password` để hiện lời nhắc nhập mật khẩu. |
| `systemd-tmpfiles-clean.timer` | Hẹn giờ chạy `systemd-tmpfiles-clean.service` mỗi ngày để dọn file tạm cũ |

## 6. Mount (filesystem)

Rootfs của dự án là read-only. Những chỗ cần ghi được lấy từ RAM (tmpfs) hoặc từ phân vùng `/data`.

| Unit | Mount point | Nhiệm vụ |
|---|---|---|
| `-.mount` | `/` | Rootfs read-only, nằm trên `rootA` hoặc `rootB` |
| `data.mount` | `/data` | Phân vùng data `mmcblk0p5` |
| `etc.mount` | `/etc` | Overlayfs: lớp dưới là `/etc` read-only của rootfs, lớp trên writeable nằm trên `/data` |
| `tmp.mount` | `/tmp` | tmpfs trong RAM |
| `var-volatile.mount` | `/var/volatile` | tmpfs trong RAM, chứa phần ghi được của `/var` |
| `var-lib.mount`, `var-cache.mount` | `/var/lib`, `/var/cache` | Overlay với lớp trên nằm trong `/var/volatile/...` để các thư mục này ghi được dù rootfs read-only. `/var/spool` và `/srv` không còn được làm cho ghi được vì không có cron, mail hay file server |
| `dev-mqueue.mount` | `/dev/mqueue` | Filesystem cho POSIX message queue. Đã bỏ khỏi image (recipe `systemd`) vì các daemon dùng Unix socket |
| `sys-kernel-debug.mount` | `/sys/kernel/debug` | debugfs, nơi kernel xuất thông tin debug. Bị mask khi distro không bật `sensornode-debug` |
| `sys-kernel-config.mount` | `/sys/kernel/config` | configfs, dùng để cấu hình USB gadget và một số subsystem kernel. Đã bỏ khỏi image vì không cấu hình USB gadget |
| `sys-fs-fuse-connections.mount` | `/sys/fs/fuse/connections` | Quản lý các kết nối FUSE (filesystem chạy ở userspace). Đã bỏ khỏi image vì không dùng FUSE |

## 7. Device

Unit `.device` chỉ active khi udev đã xử lý xong thiết bị: chạy rule, tạo symlink, nạp firmware. Thời gian của nó trong `blame` là thời gian chờ, không phải thời gian làm việc.

Một thiết bị thường có nhiều unit vì udev tạo nhiều symlink cho nó. Ví dụ phân vùng `data` xuất hiện dưới các tên `dev-mmcblk0p5.device`, `dev-disk-by\x2dlabel-data.device`, `dev-disk-by\x2duuid-...device`, `dev-disk-by\x2dpartuuid-...device`, `dev-disk-by\x2dpath-...device` và tên theo đường dẫn sysfs `sys-devices-...-mmcblk0p5.device`. Tất cả đều là cùng một thiết bị.

| Thiết bị | Là gì |
|---|---|
| `mmcblk0` | Thẻ SD, nơi chứa toàn bộ hệ thống |
| `mmcblk0p1`, `mmcblk0p3` | `bootA`, `bootB`: kernel của từng slot. U-Boot đọc trực tiếp, Linux không mount |
| `mmcblk0p2`, `mmcblk0p4` | `rootA`, `rootB`: rootfs của từng slot |
| `mmcblk0p5` | `data`, mount vào `/data` |
| `dm-0`, `dev-mapper-root` | Rootfs đi qua dm-verity: kernel kiểm tra hash từng block khi đọc. `/` được mount từ thiết bị này |
| `mmcblk1`, `mmcblk1boot0`, `mmcblk1boot1` | eMMC 4 GB có sẵn trên BBB cùng hai vùng boot phần cứng của nó. Image không dùng eMMC |
| `ttyS0` | UART debug (header J1), dùng làm serial console |
| `ttyS1`–`ttyS3` | Các cổng UART khác của SoC, dự án không dùng |
| `eth0` | Ethernet |
| `wlan0` | USB WiFi RTL8188EU, cắm vào cổng USB host |
| `musb-hdrc.0` UDC | Bộ điều khiển cổng USB client của BBB. Khi có thiết bị này thì `usb-gadget.target` được kích hoạt |
| `backlight` | Đèn nền màn hình, điều khiển bằng PWM qua `/sys/class/backlight/` |
| `sys-module-configfs`, `sys-module-fuse` | Xuất hiện khi module `configfs` và `fuse` đã có trong kernel |

## 8. Service của early boot (trước `sysinit.target`)

| Unit | Nhiệm vụ |
|---|---|
| `systemd-journald` | Thu thập log từ kernel, systemd và mọi service vào journal |
| `systemd-journal-flush` | Chuyển journal từ RAM (`/run/log/journal`) sang bộ nhớ lâu dài (`/var/log/journal`, trên `/data`) khi filesystem đã sẵn sàng |
| `kmod-static-nodes` | Tạo sẵn các node `/dev` cho module kernel khai báo trong `modules.devname`, để module tự nạp khi có chương trình mở node |
| `modprobe@drm` | Nạp sớm một module kernel trước khi các unit cần nó chạy. DRM đã build sẵn trong kernel nên unit chạy nhưng không có gì để nạp. `modprobe@configfs`, `modprobe@fuse` không còn chạy vì các mount cần chúng đã bị bỏ |
| `systemd-remount-fs` | Áp dụng tuỳ chọn mount trong fstab cho `/` (ví dụ `ro`, `noatime`) |
| `systemd-sysctl` | Áp dụng tham số kernel từ `/etc/sysctl.d/` |
| `systemd-udevd` | Daemon quản lý thiết bị: nhận uevent từ kernel, chạy rule, tạo symlink `/dev/disk/by-*`, nạp module và firmware |
| `systemd-udev-trigger` | Coldplug: yêu cầu kernel phát lại uevent cho mọi thiết bị đã có từ trước khi udevd chạy, để udevd xử lý chúng |
| `systemd-tmpfiles-setup-dev` | Tạo các node `/dev` tĩnh theo cấu hình tmpfiles |
| `systemd-tmpfiles-setup` | Tạo thư mục, file, symlink và đặt quyền theo `/etc/tmpfiles.d/` và `/usr/lib/tmpfiles.d/` (ví dụ `/run/sensornode`) |
| `var-volatile-cache`, `var-volatile-lib` | Chuẩn bị thư mục trong `/var/volatile` rồi mount lên `/var/cache`, `/var/lib` (gói `volatile-binds` của Yocto, danh sách đặt trong `volatile-binds.bbappend`) |
| `systemd-random-seed` | Nạp lại seed ngẫu nhiên đã lưu ở lần boot trước. Đã bỏ (`PACKAGECONFIG` `randomseed`) vì seed nằm trên `/var/lib` là tmpfs, không giữ được qua boot |
| `systemd-network-generator` | Đọc tham số mạng trên kernel cmdline (`ip=`, `nameserver=`) và sinh file cấu hình cho networkd. Bị mask vì bootargs không có `ip=` |
| `systemd-update-utmp` | Ghi bản ghi boot và shutdown vào `/var/log/wtmp`, dùng cho lệnh `last`. Đã bỏ (`PACKAGECONFIG` `utmp`) |
| `systemd-backlight@backlight:backlight` | Khôi phục độ sáng đã lưu khi boot và lưu lại khi tắt máy. Đã bỏ (`PACKAGECONFIG` `backlight`) vì UI tự đặt độ sáng theo giá trị lưu ở settingsd |
| `psplash-start` | Hiện màn hình splash trên framebuffer ngay đầu boot |
| `psplash-systemd` | Cập nhật thanh tiến trình của psplash theo tiến độ boot của systemd. UI gửi `psplash-write QUIT` để tắt splash |

## 9. Service hệ thống sau `basic.target`

| Unit | Nhiệm vụ |
|---|---|
| `dbus` | Bus tin nhắn hệ thống (D-Bus). logind, networkd, resolved dùng D-Bus để nhận lệnh từ `systemctl`, `hostnamectl`, `resolvectl`… |
| `systemd-logind` | Quản lý phiên đăng nhập, seat và nút nguồn/nút sleep. Chạy sau UI |
| `systemd-networkd` | Cấu hình mạng: bật interface, xin DHCP, gán IP theo các file `.network` |
| `systemd-resolved` | Phân giải tên: DNS, mDNS (`*.local`), LLMNR. Dự án cần nó để phân giải broker `NGUYEN.local`. Chạy sau UI |
| `systemd-timesyncd` | Client NTP, đồng bộ giờ khi có mạng. Giờ lúc boot do kernel đặt từ DS3231. Unit gốc chạy trong early boot (`Before=sysinit.target`), image sửa lại thành service thường chạy sau UI |
| `getty@tty1` | Màn hình đăng nhập trên console `tty1` (framebuffer). Đã tắt bằng preset, và kernel tắt `CONFIG_VT` nên không còn `tty1` |
| `serial-getty@ttyS0` | Màn hình đăng nhập trên UART debug. Chạy sau UI |
| `sshdgenkeys` | Sinh host key cho SSH nếu chưa có. Chỉ có ở distro dev. Chạy sau UI |
| `systemd-update-utmp-runlevel` | Ghi việc chuyển runlevel (đạt `multi-user.target`) vào utmp. Đã bỏ cùng `systemd-update-utmp` |
| `systemd-tmpfiles-clean` | Chạy theo timer, xoá file tạm quá hạn |

## 10. Service của dự án

| Unit | Nhiệm vụ |
|---|---|
| `sensornode-settingsd` | Lưu cài đặt của thiết bị (`/data/settings/settings.json`), trả cài đặt và báo thay đổi cho client qua Unix socket |
| `sensornode-telemetryd` | Đọc SHT30, BH1750 qua I2C mỗi 5 giây, lưu SQLite (`/data/telemetry/telemetry.db`), publish MQTT QoS 1 kèm gửi bù dữ liệu tồn đọng |
| `sensornode-otad` | Kiểm tra và cài firmware qua SWUpdate, nhận thông báo bản mới từ MQTT topic `ota/latest`. Chạy root vì ghi block device và U-Boot env |
| `sensornode-powerd` | Nhận lệnh reboot từ UI/web qua socket `/run/sensornode/power.sock` rồi chạy `systemctl reboot` |
| `sensornode-webd` | Giao diện web ở cổng 80: xem trạng thái, log, upload `.swu`, cấu hình WiFi |
| `sensornode-ui` | HMI Qt trên màn hình ILI9341: hiển thị dữ liệu, ghi backlight, là client của các daemon |
| `sensornode-wifi` | Chạy `wpa_supplicant` cho `wlan0` với cấu hình ở `/data/config/wpa_supplicant-wlan0.conf` |
| `ota-confirm-boot` | Health check sau OTA: đợi các daemon và UI chạy ổn định rồi mới xác nhận slot mới với U-Boot nếu không U-Boot sẽ rollback |

Thứ tự khởi động của các service dự án:

```
settingsd → telemetryd → sensornode-ui ─┬─ otad ───┐
                                        ├─ powerd ─┴─ webd
                                        └─ logind, timesyncd, resolved, serial-getty@ttyS0, sshdgenkeys
```

- `sensornode-ui.service` chỉ có `After=` với `data.mount`, settingsd và telemetryd, nên màn hình lên ngay khi có dữ liệu.
- otad, powerd và các unit hệ thống không cần cho màn hình có drop-in `20-sensornode-after-ui.conf` chứa `After=sensornode-ui.service`. Đây chỉ là thứ tự, không phải phụ thuộc: UI lỗi thì chúng vẫn chạy.
- webd chờ otad và powerd nên tự chạy sau UI.

## 11. Generator

Generator là chương trình PID 1 chạy trước mọi unit để sinh unit động, ví dụ sinh unit `.mount` từ `/etc/fstab`. Chúng nằm trong `/lib/systemd/system-generators/` và chạy mỗi lần boot hoặc `daemon-reload`.

| Generator | Trạng thái | Lý do |
|---|---|---|
| `systemd-fstab-generator` | Giữ | Sinh `var-volatile.mount` và các mount khác từ `/etc/fstab`. `data.mount` là unit file riêng, không đi qua generator |
| `systemd-getty-generator` | Giữ | Sinh `serial-getty@ttyS0` từ console trên kernel cmdline |
| `systemd-sysv-generator`, `systemd-rc-local-generator` | Mask | Không có script `/etc/init.d` hay `rc.local` |
| `systemd-gpt-auto-generator` | Mask | Chỉ tự tìm phân vùng khi boot qua EFI, U-Boot ở đây không boot kiểu EFI |
| `systemd-debug-generator`, `systemd-run-generator`, `systemd-system-update-generator` | Mask | Kernel cmdline do U-Boot đặt cố định, không dùng tham số `systemd.*` hay system update offline |

Generator bị mask bằng symlink `/etc/systemd/system-generators/<tên> -> /dev/null`, tạo lúc build image (`mask_unused_generators` trong `sensornode-image-common.inc`).

## 12. Công cụ đo boot

| Unit | Nhiệm vụ |
|---|---|
| `systemd-bootchart` | Lấy mẫu CPU, I/O và process trong lúc boot rồi xuất SVG vào `/run/log/`. Chỉ có khi bật feature `sensornode-devtools`, mặc định disable. Cách dùng xem lần đo 5 trong `docs/boot-optimize.md` |
