# Tối ưu thời gian boot

Nhật ký quá trình tối ưu thời gian boot của SensorNode trên BeagleBone Black. Phần đầu là phương pháp đọc `systemd-analyze` và log, phần sau ghi lại từng lần đo: số liệu, phân tích, giả thuyết, thay đổi và kết quả.

## Phương pháp

### Bước 0: Mốc thời gian của từng công cụ

| Nguồn | Mốc |
|---|---|
| `systemd-analyze critical-chain`, `blame` | Lúc systemd (PID 1) bắt đầu |
| `systemd-analyze plot` (SVG) | Lúc kernel bắt đầu |
| `journalctl -o short-monotonic`, `dmesg` | Lúc kernel bắt đầu |

Thời điểm trong SVG = thời điểm trong `critical-chain` + thời gian kernel.

`systemd-analyze` không đo U-Boot vì U-Boot không báo thời gian của nó cho systemd. Muốn đo phần U-Boot thì cần log serial có timestamp, ví dụ `grabserial -t` trên máy host.

### Bước 1: Chọn chỉ số cần tối ưu

Tối ưu boot cần phải gắn với một mốc cụ thể: màn hình hiện dashboard, mẫu đầu tiên vào DB, MQTT kết nối được hay `multi-user.target`. Mốc này quyết định unit nào nằm trên critical path. Một unit chậm mà không ai chờ nó thì tối ưu cũng không làm mốc đó đến sớm hơn.

### Bước 2: `systemd-analyze`

Cho biết tổng thời gian boot của kernel và userspace:

```bash
root@bbb-sensornode:~# systemd-analyze
Startup finished in 3.180s (kernel) + 26.926s (userspace) = 30.106s
multi-user.target reached after 26.681s in userspace
```

```
kernel start       systemd (PID 1) start        default target đạt
     |-------- kernel --------|------- userspace -------|
     |        4.970s          |        7.656s           |
```

| Mốc       | Ý nghĩa |
| --------- | ------- |
| kernel    | Từ lúc kernel bắt đầu chạy đến lúc systemd (PID 1) được start |
| userspace | Từ lúc systemd start đến lúc đạt default target |

### Bước 3: `critical-chain`

Xem chuỗi của một unit cụ thể bằng `systemd-analyze critical-chain <unit>`.

```bash
multi-user.target @26.681s
`-ota-confirm-boot.service @26.662s
  `-sensornode-ui.service @22.730s +3.884s
    `-sensornode-telemetryd.service @14.382s +8.319s
      `-sensornode-settingsd.service @11.773s +2.563s
        `-basic.target @11.445s
          `-sockets.target @11.445s
            `-sshd.socket @11.349s +92ms
              `-sysinit.target @11.304s
                `-systemd-timesyncd.service @5.501s +4.574s
                  `-systemd-tmpfiles-setup.service @4.962s +487ms
                    `-systemd-journal-flush.service @3.314s +1.587s
                      `-var-volatile.mount @3.104s +88ms
                        `-local-fs-pre.target @3.062s
                          `-systemd-tmpfiles-setup-dev.service @2.801s +257ms
                            `-kmod-static-nodes.service @1.785s +671ms
                              `-systemd-journald.socket @1.687s
                                `--.mount @1.579s
                                  `--.slice @1.579s
```

Cách đọc:
- Đọc từ dưới lên: unit ở dưới phải xong thì unit ở trên mới start được.
- `@` là lúc unit bắt đầu khởi động.
- `+` là thời gian unit đó cần để khởi động xong. Unit không có `+` là target hoặc unit start gần như tức thì.
- Với mỗi cặp cha–con, tính giờ kết thúc của con = `@` + `+` rồi so với `@` của cha. Hiệu số giữa `@` của cha và giờ kết thúc của con gọi là **slack** (thuật ngữ của Critical Path Method).

```
settingsd    @11.773 + 2.563 = 14.336  ->  telemetryd @14.382  (slack 46ms)
telemetryd   @14.382 + 8.319 = 22.701  ->  ui         @22.730  (slack 29ms)
ui           @22.730 + 3.884 = 26.614  ->  ota-confirm @26.662
```

- Slack ≈ 0 nghĩa là cha đang chờ con, con nằm trên critical path.
- Slack lớn nghĩa là cha còn đang chờ thứ khác mà chuỗi critical path không hiện.

Chuỗi `settingsd -> telemetryd -> UI` nối đuôi nhau vì có `After=` trong unit file. Rút ngắn bất kỳ mắt xích nào trong chuỗi này đều kéo `multi-user` sớm lên.

`critical-chain` chỉ in một phụ thuộc kết thúc muộn nhất, bỏ qua unit đã về inactive và không thể hiện việc systemd bận. Dùng SVG để tìm thứ đang chiếm phần slack này.

Service `Type=simple` không có `+` vì systemd coi là xong ngay khi fork nên service simple chậm sẽ không lộ ra ở đây.

### Bước 4: `blame`

`blame` chỉ sắp theo thời gian khởi động của từng unit, không quan tâm unit có nằm trên critical path hay không. Cách đọc:

1. Đối chiếu với `critical-chain`: unit có mặt ở cả hai là ưu tiên số 1.
2. Unit `.device` là thời gian chờ udev báo thiết bị, không phải thời gian làm việc. Số lớn ở đây phản ánh udev coldplug đang chậm.
3. Tìm số bất thường so với kỳ vọng. Khi mọi unit đều chậm đều nhau, thủ phạm thường là tranh CPU/IO chứ không phải từng unit.
4. Unit ngoài critical path vẫn có thể gây hại vì ngốn CPU đúng lúc các unit trên critical path đang chạy.

### Bước 5: SVG

Tạo bằng `systemd-analyze plot > boot.svg` rồi mở bằng trình duyệt sẽ thấy biểu đồ thời gian. Nhìn hình dạng, chưa cần đọc từng dòng:
- Đỏ là đang khởi động, hồng là đã active.
- Nhiều thanh đỏ chồng nhau: tranh tài nguyên.
- Một thanh đỏ dài đứng một mình: điểm nghẽn. Nếu lúc đó CPU rảnh mà vẫn chậm thì unit đang chờ I/O, mạng hoặc timeout.
- Khoảng trống bên trái của một unit: nó đang chờ phụ thuộc.

### Bước 6: Journal và code

`+8.319s` chỉ là một con số. Để biết thời gian đi đâu, xem log của unit với timestamp tính từ lúc boot rồi tìm Δt lớn giữa hai dòng log liên tiếp, sau đó đọc code giữa hai dòng log đó:

```sh
journalctl -b -o short-monotonic -u <unit>
```

Phần kernel thì dùng `dmesg` để tìm driver probe chậm.

### Bước 7: Sửa một thứ, đo lại nhiều lần

- Mỗi lần chỉ đổi một thứ để biết thay đổi nào có tác dụng.
- Boot 3–5 lần và lấy trung vị; trên thẻ SD dao động ±0.5s là bình thường.
- So sánh cùng chỉ số đã chọn ở bước 1.
- Bỏ được một mắt xích thì critical path đổi sang chuỗi khác, quay lại bước 3.

## Lần đo 0: Baseline

### Số liệu

```bash
root@bbb-sensornode:~# systemd-analyze
Startup finished in 3.180s (kernel) + 26.926s (userspace) = 30.106s
multi-user.target reached after 26.681s in userspace
```

```bash
root@bbb-sensornode:~# systemd-analyze critical-chain
The time when unit became active or started is printed after the "@" character.
The time the unit took to start is printed after the "+" character.

multi-user.target @26.681s
`-ota-confirm-boot.service @26.662s
  `-sensornode-ui.service @22.730s +3.884s
    `-sensornode-telemetryd.service @14.382s +8.319s
      `-sensornode-settingsd.service @11.773s +2.563s
        `-basic.target @11.445s
          `-sockets.target @11.445s
            `-sshd.socket @11.349s +92ms
              `-sysinit.target @11.304s
                `-systemd-timesyncd.service @5.501s +4.574s
                  `-systemd-tmpfiles-setup.service @4.962s +487ms
                    `-systemd-journal-flush.service @3.314s +1.587s
                      `-var-volatile.mount @3.104s +88ms
                        `-local-fs-pre.target @3.062s
                          `-systemd-tmpfiles-setup-dev.service @2.801s +257ms
                            `-kmod-static-nodes.service @1.785s +671ms
                              `-systemd-journald.socket @1.687s
                                `--.mount @1.579s
                                  `--.slice @1.579s
```

```bash
@bbb-sensornode:~# systemd-analyze blame
9.544s dev-mapper-root.device
9.151s dev-mmcblk0p5.device
8.319s sensornode-telemetryd.service
5.482s systemd-resolved.service
4.574s systemd-timesyncd.service
4.476s systemd-udev-trigger.service
3.884s sensornode-ui.service
2.596s sensornode-powerd.service
2.563s sensornode-settingsd.service
2.337s sensornode-otad.service
2.060s systemd-networkd.service
2.055s systemd-logind.service
1.587s systemd-journal-flush.service
1.572s sshdgenkeys.service
1.261s sensornode-webd.service
 881ms systemd-journald.service
 780ms systemd-udevd.service
 711ms dev-mqueue.mount
 692ms sys-kernel-debug.mount
 671ms kmod-static-nodes.service
 664ms modprobe@configfs.service
 655ms tmp.mount
 651ms modprobe@drm.service
 631ms modprobe@fuse.service
 626ms dbus.service
 539ms var-volatile-lib.service
 514ms var-volatile-cache.service
 512ms systemd-network-generator.service
 495ms systemd-remount-fs.service
 489ms var-volatile-spool.service
 487ms systemd-tmpfiles-setup.service
 448ms systemd-sysctl.service
 435ms var-volatile-srv.service
 364ms systemd-backlight@backlight:backlight.service
 345ms psplash-start.service
 292ms systemd-update-utmp.service
 257ms systemd-tmpfiles-setup-dev.service
 230ms systemd-random-seed.service
 198ms sys-fs-fuse-connections.mount
 177ms systemd-update-utmp-runlevel.service
 149ms sys-kernel-config.mount
 100ms systemd-tmpfiles-clean.service
  92ms sshd.socket
  88ms var-volatile.mount
  63ms modprobe@efi_pstore.service
```

### Phân tích

Log `systemd-analyze` cho biết kernel mất 3.2s, userspace mất 26.9s. Userspace chiếm gần 90% nên tập trung tối ưu vào userspace. Kernel và U-Boot để sau.

Nhìn vào kết quả của `blame` và `critical-chain`, ta có bảng các unit mất nhiều thời gian và nằm trên critical path như sau:

| Unit | `blame` |
|---|---|
| `sensornode-telemetryd` | 8.319s |
| `systemd-timesyncd` | 4.574s |
| `sensornode-ui` | 3.884s |
| `sensornode-settingsd` | 2.563s |

Ta thấy thời gian telemetryd khởi động quá lâu, chiếm khoảng 31% userspace. Ngoài ra, nhìn vào SVG ở đoạn telemetryd khởi động. Ta thấy thanh đỏ của telemetryd đứng một mình, gần như không có unit nào khác chạy song song. CPU rảnh mà telemetryd vẫn chưa ready nên nó đang chờ thứ gì đó (I/O, mạng hoặc timeout), không phải thiếu CPU.

telemetryd khởi động chậm kéo theo chuỗi các unit phía sau phụ thuộc vào nó chậm theo nên ta sẽ tập trung tối ưu unit này trước.

Thực hiện lấy log journald của unit telemetryd để biết nó đang chờ gì:

```sh
journalctl -b -o short-monotonic -u sensornode-telemetryd | head -30
```

```
root@bbb-sensornode:~# journalctl -b -o short-monotonic -u sensornode-telemetryd
[   17.632575] bbb-sensornode systemd[1]: Starting SensorNode telemetry daemon...
[   18.281582] bbb-sensornode sensornode-telemetryd[219]: main: starting version=0.1.0 git=7634b95-dirty pid=219
[   18.288787] bbb-sensornode sensornode-telemetryd[219]: main: config node=64cfd9d72124 interval=5000ms log_level=info
[   18.288787] bbb-sensornode sensornode-telemetryd[219]: sensor: using i2c bus=/dev/i2c-1 sht30=0x44 bh1750=0x23
[   18.372576] bbb-sensornode sensornode-telemetryd[219]: db: opened path=/data/telemetry/telemetry.db
[   18.375171] bbb-sensornode sensornode-telemetryd[219]: ipc: listening path=/run/sensornode/telemetry.sock
[   18.380798] bbb-sensornode sensornode-telemetryd[219]: mqtt: broker host=NGUYEN.local port=1883 client_id=telemetryd-64cfd9d72124 topic=sensornode/64cfd9d72124/#
[   25.995907] bbb-sensornode sensornode-telemetryd[219]: mqtt: disconnected: Lookup error. retry_in=1s src=main.cpp:343
[   26.052804] bbb-sensornode sensornode-telemetryd[219]: db: maintenance done hours_aggregated=1 raw_purged=649 hourly_purged=0 took=48ms
[   26.054042] bbb-sensornode sensornode-telemetryd[219]: systemd: watchdog enabled timeout=30000ms
[   26.056434] bbb-sensornode sensornode-telemetryd[219]: ipc: connected path=/run/sensornode/settings.sock
[   26.071653] bbb-sensornode sensornode-telemetryd[219]: main: ready
[   26.072808] bbb-sensornode systemd[1]: Started SensorNode telemetry daemon.
[   27.321681] bbb-sensornode sensornode-telemetryd[219]: ipc: client connected cid=1 pid=225 uid=999 gid=999
[   27.376409] bbb-sensornode sensornode-telemetryd[219]: mqtt: connected host=NGUYEN.local port=1883
[   29.469685] bbb-sensornode sensornode-telemetryd[219]: ipc: client connected cid=2 pid=227 uid=999 gid=999
```

Nhìn vào log, ta thấy thời gian từ dòng `mqtt: broker host=` đến dòng `mqtt: disconnected: Lookup error` mất khoảng 7.6s. Và dòng mqtt disconnect này có lỗi là `Lookup error`, lỗi này là lỗi phân giải broker.

Bên trong libmosquitto, tuy `mosquitto_connect_async()` chỉ làm phần connect TCP theo chế độ non-blocking. Nhưng trước đó nó vẫn gọi `getaddrinfo()` blocking để đổi tên host thành địa chỉ IP. Như vậy hàm đứng chờ tra mDNS ở thời điểm mạng có thể chưa lên. Phân giải thất bại thì hàm trả về `MOSQ_ERR_EAI`, chuỗi lỗi của mã này là `Lookup error`.


**Phương án**

| Phương án | Ý tưởng | Đánh giá |
|---|---|---|
| A. Đổi broker sang IP | Bỏ `NGUYEN.local`, dùng IP cố định nên không cần lookup | Chỉ né lỗi. |
| B. Báo `READY=1` trước rồi mới kết nối broker | Đẩy `use_broker()` ra sau `READY=1` | UI start sớm hơn nhưng event loop vẫn treo 7.6s ngay sau đó nên UI kết nối vào cũng không được trả lời |
| **C. Phân giải tên bất đồng bộ** | Tra tên ngoài event loop (thread riêng hoặc hỏi systemd-resolved qua socket), có IP rồi mới gọi `mosquitto_connect_async()` với IP | Sửa đúng root cause, áp dụng cho cả lần reconnect |

**Kết quả**

```bash
root@bbb-sensornode:~# systemd-analyze
Startup finished in 3.183s (kernel) + 20.067s (userspace) = 23.250s
multi-user.target reached after 19.752s in userspace
```

-> Giảm khoảng 6.9s so với ban đầu

Tiếp theo, ta loại bỏ các unit mà thiết bị không dùng tới. Phần lớn những unit này chạy trong giai đoạn `sysinit` và đang tranh CPU với các unit trên critical path. Kiểm tra một unit có thuộc giai đoạn này không bằng `systemctl show -p Before <unit>`.

| Unit | Time | Là gì | Vì sao loại |
|---|---|---|---|
| `systemd-logind` | 1.98s | Quản lý đăng nhập, nút nguồn | Thiết bị không có người dùng đăng nhập ở màn hình. UI chạy bằng `User=` trong service, powerd reboot bằng `systemctl reboot` với quyền root nên không đi qua logind |
| `modprobe@drm` | 682ms | Nạp module DRM | DRM đã build sẵn trong kernel (`CONFIG_TINYDRM_ILI9341=y`), không còn module nào để nạp |
| `dev-mqueue.mount` | 688ms | Mount POSIX message queue | Các daemon giao tiếp qua Unix socket, không dùng POSIX message queue |
| `sys-kernel-debug.mount` | 668ms | Mount debugfs | Chỉ dùng khi debug kernel. Giữ ở distro dev, bỏ ở production |
| `modprobe@fuse`, `sys-fs-fuse-connections.mount` | 654ms, 227ms | Hỗ trợ filesystem chạy ở userspace (FUSE) | Không có filesystem FUSE nào được dùng |
| `modprobe@configfs`, `sys-kernel-config.mount` | 679ms, 189ms | configfs, dùng cho USB gadget | Image không cấu hình USB gadget |
| `systemd-network-generator` | 536ms | Sinh file `.network` từ tham số `ip=` trên kernel cmdline | Bootargs không có `ip=` và mạng cấu hình bằng file `10-eth0.network` |
| `systemd-backlight@backlight:backlight` | 370ms | Lưu và khôi phục độ sáng màn hình qua các lần boot | UI tự ghi backlight theo giá trị lưu ở settingsd, nên hai bên ghi đè lên nhau |
| `systemd-update-utmp`, `systemd-update-utmp-runlevel` | 259ms, 225ms | Ghi log đăng nhập và runlevel vào utmp/wtmp | Chỉ phục vụ lệnh `who` và `last`, thiết bị không cần |
| `getty@tty1` | | Màn hình đăng nhập trên console framebuffer | Màn hình thuộc về UI và không có bàn phím. Console serial `ttyS0` vẫn giữ để debug |
| `modprobe@efi_pstore` | 71ms | Lưu log kernel panic vào biến EFI | BBB không có EFI |

Không bỏ được:

| Unit | Lý do |
|---|---|
| `systemd-resolved` | Cần cho mDNS |
| `systemd-timesyncd`, `systemd-networkd` | NTP và mạng |
| `systemd-journal-flush` | Ghi journal persistent xuống `/data` |
| `psplash-*` | Hiện màn hình splash cho tới khi UI khởi động |
| `sshdgenkeys` | Chỉ có ở distro dev, image production không có sshd |

> Lưu ý: Bỏ `systemd-logind` thì mất xử lý nút nguồn: bấm nút POWER không còn tắt máy an toàn qua systemd. Nhấn giữ nút để PMIC cắt nguồn cứng vẫn hoạt động.

**Kết quả**

```bash
root@bbb-sensornode:~# systemd-analyze
Startup finished in 3.167s (kernel) + 19.169s (userspace) = 22.336s 
multi-user.target reached after 19.163s in userspace
```

-> Giảm khoảng 0.589 so với trước.

## Lần đo 1: Đưa `systemd-timesyncd` ra khỏi `sysinit.target`

### Số liệu

```bash
root@bbb-sensornode:~# systemd-analyze critical-chain
multi-user.target @19.163s
└─ota-confirm-boot.service @19.141s
  └─sensornode-ui.service @15.064s +4.024s
    └─sensornode-telemetryd.service @13.140s +1.871s
      └─sensornode-settingsd.service @10.306s +2.769s
        └─basic.target @10.045s
          └─sockets.target @10.045s
            └─sshd.socket @7.124s +933ms
              └─sysinit.target @7.007s
                └─systemd-timesyncd.service @4.476s +2.525s
                  └─systemd-tmpfiles-setup.service @3.731s +650ms
                  ...
```

### Phân tích

Unit gốc của timesyncd khai báo `DefaultDependencies=no`, `Before=time-set.target sysinit.target` và `WantedBy=sysinit.target`. Nó chạy trong early boot để đẩy đồng hồ lên ít nhất bằng mốc thời gian đã lưu ở `/var/lib/systemd/timesync/clock`. Trên SensorNode, việc này không còn ý nghĩa:

- Kernel đã đặt giờ từ DS3231 trước khi systemd chạy:

```bash
root@bbb-sensornode:~# dmesg | grep -iE "rtc|hctosys"
rtc-ds1307 1-0068: registered as rtc0
rtc-ds1307 1-0068: setting system clock to 2026-11-25T08:44:59 UTC (1795596299)
```

- `/var/lib` là tmpfs nên mốc thời gian timesyncd lưu không giữ được qua reboot.

→ timesyncd chỉ còn việc đồng bộ NTP khi có mạng, chạy như service thường là đủ.

### Thay đổi

Không sửa unit trong recipe `systemd` vì thay đổi sysroot của systemd kéo theo build lại qtbase. Thay vào đó, `move_timesyncd_off_sysinit` trong `sensornode-image-common.inc` sửa unit ngay trong rootfs lúc tạo image: bỏ `DefaultDependencies=no`, `Before=...sysinit.target...`, `Wants=time-set.target`, đổi `WantedBy=` sang `multi-user.target` và chuyển symlink sang `multi-user.target.wants`. Nếu upstream đổi nội dung unit khiến `sed` không khớp, build dừng bằng `bbfatal`.

### Kết quả

```bash
root@bbb-sensornode:~# systemd-analyze
Startup finished in 3.167s (kernel) + 19.100s (userspace) = 22.268s
multi-user.target reached after 19.086s in userspace

root@bbb-sensornode:~# systemd-analyze critical-chain
multi-user.target @19.086s
└─ota-confirm-boot.service @19.074s
  └─sensornode-ui.service @14.647s +4.375s
    └─sensornode-telemetryd.service @12.544s +2.020s
      └─sensornode-settingsd.service @6.776s +4.847s
        └─basic.target @6.075s
          └─sockets.target @6.075s
            └─sshd.socket @5.913s +158ms
              └─sysinit.target @5.779s
                └─systemd-udev-trigger.service @1.797s +3.960s
```

→ `sysinit.target` đến sớm hơn 1.2s (7.007s → 5.779s) nhưng `multi-user.target` gần như không đổi (19.163s → 19.086s). Phần thời gian tiết kiệm được bị nuốt ở phía sau: settingsd mất 4.847s thay vì 2.769s.

`blame` của lần boot này cho thấy hầu hết service đều chậm đều nhau:

```
 5.274s sensornode-otad.service
 5.152s systemd-logind.service
 5.051s sensornode-powerd.service
 5.017s systemd-resolved.service
 4.847s sensornode-settingsd.service
 4.375s sensornode-ui.service
```

→ Theo bước 4 của phần phương pháp, đây là dấu hiệu tranh CPU. BBB chỉ có một nhân Cortex-A8: kéo một unit lên sớm hơn thì nó lại phải chia CPU với các unit khác đang chạy cùng lúc.

## Lần đo 2: Thử hạ ưu tiên CPU bằng `Nice=` (không áp dụng)

Thử bằng drop-in tạm trong `/etc/systemd/system/<unit>.d/`, mỗi cấu hình boot 2 lần. Thời gian tính từ lúc userspace bắt đầu:

| Cấu hình | UI sẵn sàng (trung bình) | `multi-user` (trung bình) |
|---|---|---|
| A: như hiện tại | 19.28s | 19.37s |
| B: `Nice=10` cho webd, timesyncd, logind, getty | 18.52s | 18.65s |
| C: B, thêm `Nice=-5` cho settingsd, telemetryd, otad, powerd, resolved, UI | 17.98s | 18.59s |

Giữa hai lần boot cùng cấu hình lệch nhau 0.3–0.5s. Đo CPU ngay sau boot thì thời gian ở kernel (11.3s) nhiều hơn ở chương trình (9.0s), mà `Nice=` không tác động được phần kernel (fork/exec, page fault, dm-verity tính hash khi đọc thẻ SD).

→ Lợi khoảng 1s cho UI nhưng không ổn định, nên không đưa vào image. Các drop-in thử nghiệm đã xoá khỏi board.

## Lần đo 3: Sắp lại thứ tự khởi động

### Phân tích

Trước đây UI chờ cả otad, powerd và `network.target`. Các service không cần cho màn hình (logind, timesyncd, resolved, getty serial, sshdgenkeys) chạy cùng lúc với chuỗi settingsd → telemetryd → UI và tranh CPU với chuỗi này.

Kiểm tra trước khi đổi thứ tự:

- UI dùng `DaemonClient` tự kết nối lại mỗi 2s, nên daemon lên sau UI vẫn được nhận. Khi nối được, `OtaModel` gửi `status` để lấy lại trạng thái.
- `ota-confirm-boot` vẫn chờ otad và UI, cửa sổ health check 120s, nên otad lên muộn vài giây chỉ làm slot được commit muộn theo.
- Chỉ dùng `After=` (thứ tự), không dùng `Requires=`, nên service sau UI vẫn chạy kể cả khi UI lỗi.

### Thay đổi

```
settingsd → telemetryd → sensornode-ui ─┬─ otad ───┐
                                        ├─ powerd ─┴─ webd
                                        └─ logind, timesyncd, resolved, serial-getty@ttyS0, sshdgenkeys
```

- `sensornode-ui.service` chỉ còn `After=data.mount sensornode-settingsd.service sensornode-telemetryd.service`. `Wants=` giữ nguyên để UI vẫn kéo các daemon lên.
- Drop-in `20-sensornode-after-ui.conf` (`After=sensornode-ui.service`) cài cho otad, powerd (recipe `sensornode-core`) và các unit hệ thống trong `SENSORNODE_AFTER_UI_UNITS` (recipe `systemd-conf`).
- webd giữ `After=` otad và powerd như cũ nên tự chạy sau UI.

### Kết quả

Đo 2 lần boot với thứ tự mới (thời gian tính từ lúc userspace bắt đầu):

```
D1 + 18.598s (userspace) basic=5.98 settingsd=9.71 telemetryd=11.23 ui=14.85 multi=18.55
D2 + 18.062s (userspace) basic=5.98 settingsd=9.71 telemetryd=11.12 ui=14.77 multi=18.03
```

`journalctl -b | grep -ciE "ordering cycle"` trả về `0` ở cả hai lần.

→ UI sẵn sàng sớm hơn khoảng 4.5s (19.28s → 14.8s). `multi-user.target` sớm hơn khoảng 1s vì tổng lượng việc không đổi, chỉ dời ra sau UI.

## Lần đo 4: Vì sao settingsd mất khoảng 3s

### Số liệu

```
 9.446  systemd: Starting SensorNode settings daemon...
12.840  settingsd: main: starting
12.919  settingsd: main: ready
```

`ExecMainStartTimestampMonotonic` của settingsd là 9.4398s, tức PID 1 fork ra tiến trình con gần như ngay lúc in `Starting`. Code của settingsd từ `main()` tới `ready` chỉ mất khoảng 80ms. 3.4s còn lại là thời gian tiến trình con vẫn chạy code của systemd để dựng môi trường cho service.

### Phân tích

Chạy settingsd bằng unit tạm (`systemd-run`) lúc board rảnh, socket và file settings để trong `/tmp`, mỗi trường hợp 3 lần:

| Trường hợp | Từ lúc start tới `READY` |
|---|---|
| Không sandbox | 0.16s (phần lớn là chi phí của `systemd-run`) |
| Sandbox đầy đủ như unit thật | 0.49s |
| Sandbox đầy đủ, cache nguội | 0.68s |
| Giữ sandbox, bỏ các tuỳ chọn tạo mount namespace | 0.16s |

→ Phần tốn kém là các tuỳ chọn tạo mount namespace (`ProtectSystem`, `ProtectHome`, `PrivateTmp`, `ProtectKernelTunables`,...), khoảng 0.33s ngay cả khi board rảnh, riêng `ProtectKernelTunables` khoảng 0.17s. Lúc boot, CPU đang bận nên con số này phình lên vài giây.

Bootchart (xem lần đo 5) cho thấy trong lúc settingsd dựng sandbox, process tranh CPU với nó là udev coldplug chứ không phải dbus.

### Quyết định

Giữ nguyên sandbox của các daemon. Bỏ `ProtectKernelTunables` lợi khoảng vài trăm ms nhưng đổi lại daemon không còn bị chặn ghi vào `/proc/sys` và `/sys`, không đáng.

## Lần đo 5: Bootchart, udev coldplug và VT

### Bootchart

`systemd-bootchart` được thêm vào feature `sensornode-devtools` nhưng mặc định không bật. Drop-in `10-sensornode-bootchart.conf` cho nó lấy 1000 mẫu ở 25 Hz (40s) và không dùng `-r`, nên trục thời gian tính từ lúc kernel khởi động, khớp với `journalctl -o short-monotonic`.

Bật cho một lần boot trên board:

```sh
systemctl enable systemd-bootchart   # chạy trên board, không phải máy host
reboot
# sau khi boot xong
ls /run/log/bootchart-*.svg
systemctl disable systemd-bootchart
```

`systemctl enable` ghi symlink vào `/etc`, mà `/etc` là overlay trên `/data` nên tồn tại qua reboot và OTA. Đo xong phải `disable`. Bootchart lấy mẫu `/proc` liên tục nên làm boot chậm hơn (lần đo có bootchart: 25.365s), chỉ dùng để xem process nào chiếm CPU, không dùng để đo thời gian.

File ví dụ: `docs/bootchart-20261125-1230.svg`.

### Phân tích

`systemd-udev-trigger` nằm trên critical path với +3.960s (lần đo 1). Lệnh `udevadm trigger` mặc định phát lại uevent cho mọi thiết bị trong `/sys`, kể cả những subsystem không có rule nào làm gì:

| Subsystem | Là gì |
|---|---|
| `dma` | Các kênh DMA của EDMA, không có node trong `/dev` |
| `devlink` | Liên kết phụ thuộc giữa các thiết bị trong kernel (device link), chỉ là thông tin trong sysfs |
| `vc` | Virtual console `vcs*`, `vcsa*` |

Virtual terminal (`tty0`–`tty63`, `vcs*`) là console văn bản của kernel trên màn hình. SensorNode không dùng: fbcon đã tắt, màn hình thuộc về UI, console đăng nhập là `ttyS0`.

### Thay đổi

- Drop-in `20-sensornode-udev-trigger.conf` cho `systemd-udev-trigger.service`:

```ini
[Service]
ExecStart=
ExecStart=-udevadm trigger --type=subsystems --action=add
ExecStart=-udevadm trigger --type=devices --action=add --subsystem-nomatch=dma --subsystem-nomatch=devlink --subsystem-nomatch=vc
```

- Kernel tắt `CONFIG_VT` trong `bbb_sensornode.cfg`. Không còn `/dev/tty0`, `/dev/tty1`, `/dev/vcs*` và `getty@tty1`.

### Kết quả

```bash
root@bbb-sensornode:~# systemd-analyze
Startup finished in 3.131s (kernel) + 17.189s (userspace) = 20.321s
multi-user.target reached after 17.160s in userspace

root@bbb-sensornode:~# systemd-analyze critical-chain sensornode-ui.service
sensornode-ui.service +3.479s
`-sensornode-telemetryd.service @8.975s +996ms
  `-sensornode-settingsd.service @6.775s +1.823s
    `-basic.target @5.938s
      `-sockets.target @5.906s
        `-sshd.socket @5.337s +356ms
          `-sysinit.target @5.213s
            `-systemd-tmpfiles-setup.service @4.146s +1.041s
```

```
systemd-udev-trigger=4.63 sysinit.target=5.21 basic.target=5.94 sensornode-settingsd=8.60 sensornode-telemetryd=9.97 sensornode-ui=13.47 sensornode-otad=15.00 sensornode-webd=17.15 multi-user.target=17.16
```

→ udev trigger rời khỏi critical path. UI sẵn sàng ở 13.47s (trước 14.8s), `multi-user.target` ở 17.16s. Splash, cảm ứng và đăng nhập qua serial vẫn hoạt động.

## Lần đo 6: Generator và hwdb

### Phân tích

Trước khi chạy unit nào, PID 1 chạy các generator trong `/lib/systemd/system-generators/` để sinh unit động. Phần lớn generator không có việc gì để làm trên thiết bị này:

| Generator | Vì sao không cần |
|---|---|
| `systemd-sysv-generator`, `systemd-rc-local-generator` | Không có `/etc/init.d`, `rc.local` |
| `systemd-gpt-auto-generator` | Thẻ SD dùng GPT nhưng rootfs chỉ định bằng `root=` và `/data` mount theo fstab. Generator này chỉ tự tìm phân vùng khi boot qua EFI, mà U-Boot ở đây không boot kiểu EFI |
| `systemd-debug-generator`, `systemd-run-generator`, `systemd-system-update-generator` | Kernel cmdline do U-Boot đặt cố định, không có tham số `systemd.*` hay system update offline |

Chỉ giữ `systemd-fstab-generator` và `systemd-getty-generator`.

`hwdb.bin` (9.7 MB) chỉ bổ sung tên hãng, sơ đồ phím, thông số chuột và touchpad. Cảm ứng của SensorNode không cần nó.

### Thay đổi

- `mask_unused_generators` trong `sensornode-image-common.inc` tạo symlink `/etc/systemd/system-generators/<tên> -> /dev/null` để vô hiệu từng generator.
- `BAD_RECOMMENDATIONS += "udev-hwdb"` để không cài hwdb.

### Kết quả

```bash
root@bbb-sensornode:~# systemd-analyze
Startup finished in 3.103s (kernel) + 16.254s (userspace) = 19.357s
multi-user.target reached after 16.243s in userspace
```

```
systemd-udevd=2.98 systemd-udev-trigger=3.93 sysinit.target=4.39 basic.target=4.95 sensornode-settingsd=7.46 sensornode-telemetryd=8.93 sensornode-ui=12.69 sensornode-otad=14.26 sensornode-powerd=14.94 sensornode-webd=16.22 multi-user.target=16.24
```

→ UI sẵn sàng ở 12.69s, `multi-user.target` ở 16.24s.

> [!NOTE]
> Image của lần đo này còn bỏ `ProtectKernelTunables` ở settingsd, telemetryd và webd. Thay đổi đó đã được hoàn tác (xem lần đo 4) nên số liệu trên lạc quan hơn cấu hình hiện tại vài trăm ms.

## Lần đo 7: `sensornode-ui`

### Số liệu

Lúc boot, `critical-chain` cho UI khoảng +3.6s. Theo journal:

```
[   12.611124] systemd[1]: Started SensorNode telemetry daemon.
[   13.980281] sensornode-ui[185]: QStandardPaths: XDG_RUNTIME_DIR not set, ...
[   16.220207] systemd[1]: Started SensorNode Qt HMI.
```

→ Khoảng 1.4s trước khi Qt khởi tạo (`ExecStartPre`, exec, nạp thư viện) và 2.2s trong app tới khung hình đầu tiên.

Restart UI lúc board rảnh, lấy `InactiveExitTimestampMonotonic` và `ActiveEnterTimestampMonotonic` của unit:

```
base run1: 1252 ms
base run2: 1266 ms
base run3: 1265 ms
```

→ Lúc rảnh UI chỉ mất 1.25s: khoảng 0.28s tới lúc Qt khởi tạo và 1.0s từ đó tới khung hình đầu. Lúc boot gấp gần 3 lần do tranh CPU.

### Các hướng đã thử

| Thử | Cách đo | Kết quả |
|---|---|---|
| `QT_QPA_FB_DISABLE_INPUT=1`, chỉ định thẳng `evdevtouch:/dev/input/event0`, `TZ=UTC0` | Drop-in tạm trong `/run`, restart 3 lần | 1.25s → 1.24s |
| Cache fontconfig hợp lệ | Chép lại cache gốc của image (lệch mtime) rồi restart 3 lần | 1.28s so với 1.26s |
| Bỏ `After=sensornode-telemetryd.service` cho UI | Override tạm trong `/etc`, reboot | UI sẵn sàng 16.07s so với 16.22s, nhưng UI mất +4.478s thay vì +3.590s |

→ Không hướng nào đáng áp dụng. Start UI sớm hơn chỉ làm nó chia CPU với telemetryd. Muốn UI lên nhanh hơn phải giảm lượng việc CPU làm trước khung hình đầu (dựng màn hình lười, hoãn việc không cần cho khung hình đầu) chứ không phải đổi thứ tự.

> [!NOTE]
> Lần đầu phân tích bằng `strace -f -tt`, các bước nhiều syscall (liệt kê thiết bị qua udev, fontconfig, 153 lần mở `/etc/localtime` không tồn tại) trông như tốn hàng trăm ms. Đo lại không qua `strace` thì chênh lệch chỉ khoảng 20ms. `strace` làm mỗi syscall chậm đi nhiều nên không dùng để ước lượng thời gian.

### Phát hiện phụ: cảm ứng không đi qua tslib

`ExecStart` của UI có `-plugin=tslib`, nhưng Qt 5.15 chỉ nhận dạng `-plugin tslib` (hai tham số). Trên board, process UI không nạp plugin generic nào:

```sh
P=$(systemctl show -p MainPID --value sensornode-ui)
grep -E "plugins/generic" /proc/$P/maps        # không có dòng nào
```

Cảm ứng hiện đi qua `QEvdevTouchManager` có sẵn trong plugin linuxfb, handler này không đọc `pointercal`. Vì vậy chức năng hiệu chỉnh cảm ứng trong UI ghi `pointercal` nhưng không có tác dụng. Trên board cũng không có file `pointercal` nào. Chưa sửa trong đợt tối ưu boot này.

## Tổng kết

| Lần đo | Thay đổi | Kernel + userspace | UI sẵn sàng (userspace) |
|---|---|---|---|
| 0 | Baseline | 3.180s + 26.926s = 30.106s | 22.730s + 3.884s |
| 0 | Phân giải tên broker bất đồng bộ | 3.183s + 20.067s = 23.250s | |
| 0 | Bỏ unit không dùng | 3.167s + 19.169s = 22.336s | 15.064s + 4.024s |
| 1 | timesyncd ra khỏi sysinit | 3.167s + 19.100s = 22.268s | 14.647s + 4.375s |
| 3 | Sắp lại thứ tự | userspace 18.06–18.60s | 14.8s |
| 5 | udev coldplug, tắt VT | 3.131s + 17.189s = 20.321s | 13.47s |
| 6 | Mask generator, bỏ hwdb | 3.103s + 16.254s = 19.357s | 12.69s |

Còn lại để làm tiếp:

- Giảm việc trong UI trước khung hình đầu (khoảng 1.0s lúc rảnh).
- Phân tích kernel (3.1s) bằng `initcall_debug`, cần sửa bootargs trong U-Boot.
- Đo U-Boot bằng log serial có timestamp.
