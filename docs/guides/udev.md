# udev: quản lý thiết bị trong Linux

udev là thành phần biến một thiết bị mà kernel vừa phát hiện thành một thiết bị chương trình dùng được: có node trong `/dev` với đúng quyền, có tên ổn định, có driver và firmware được nạp, và systemd biết thiết bị đã sẵn sàng. Guide này giải thích udev làm việc thế nào, cách đọc và viết rule, và udev liên quan gì tới thời gian boot của SensorNode.

## 1. Bài toán udev giải quyết

Khi kernel phát hiện một thiết bị (thẻ SD, cổng I2C, card mạng, màn hình cảm ứng,...), kernel tự làm được ba việc:

1. Driver nhận thiết bị (probe) và tạo một thư mục mô tả nó trong `/sys`.
2. devtmpfs tạo node trong `/dev` (ví dụ `/dev/i2c-1`) với owner `root:root`, quyền mặc định của kernel.
3. Kernel phát một thông báo gọi là **uevent** ra userspace.

Kernel không biết chính sách của hệ thống: ai được dùng thiết bị, đặt tên nào cho dễ tìm, cần nạp module hay firmware gì. Đó là việc của udev. Không có udev thì:

- `/dev/i2c-1` chỉ root dùng được, telemetryd (chạy user `sensornode`) không đọc được cảm biến.
- Không có `/dev/disk/by-label/data`, muốn mount `/data` phải ghi cứng `/dev/mmcblk0p5`.
- Module và firmware (ví dụ firmware của WiFi RTL8188EU) không tự nạp khi cắm thiết bị.
- systemd không biết thiết bị nào đã sẵn sàng, nên không xếp được thứ tự mount và service.

## 2. Đường đi của một thiết bị

```
 Kernel                                 Userspace
┌────────────────────────┐
│ driver probe thiết bị  │
│   ├─ tạo /sys/devices/…│
│   ├─ devtmpfs tạo /dev │
│   └─ phát uevent ──────┼──netlink──► systemd-udevd
└────────────────────────┘                │
                                          ├─ đọc thuộc tính trong /sys
                                          ├─ so khớp với các rule
                                          └─ thực hiện hành động:
                                             + đặt owner, group, mode cho /dev/...
                                             + tạo symlink /dev/disk/by-*/...
                                             + nạp module, firmware
                                             + chạy chương trình (RUN)
                                             + báo systemd ──► unit .device active
```

## 3. Các thành phần

| Thành phần | Là gì |
|---|---|
| `/sys` (sysfs) | Kernel xuất cây thiết bị ra đây. Mỗi thiết bị là một thư mục chứa thuộc tính dạng file, ví dụ `/sys/class/backlight/backlight/brightness` |
| devtmpfs | Filesystem gắn vào `/dev`. Kernel tự tạo và xoá node thiết bị trong đó |
| uevent | Thông báo kernel gửi khi thiết bị được thêm (`add`), xoá (`remove`), thay đổi (`change`)… |
| `systemd-udevd` | Daemon nhận uevent, áp dụng rule, thực hiện hành động |
| Rule | File `*.rules` mô tả "nếu thiết bị có đặc điểm X thì làm Y" |
| hwdb | Cơ sở dữ liệu phần cứng (ví dụ tên hãng theo USB ID), rule dùng để tra cứu. Image SensorNode không cài hwdb (gói `udev-hwdb`) vì không có rule nào của dự án cần |
| `udevadm` | Công cụ dòng lệnh để xem, theo dõi, test và kích hoạt udev |

## 4. Một uevent chứa gì

Theo dõi uevent trực tiếp trên board:

```sh
udevadm monitor --kernel --udev --property
```

Rồi rút hoặc cắm USB WiFi. Mỗi sự kiện in hai lần: dòng `KERNEL` là uevent gốc từ kernel, dòng `UDEV` là sau khi udevd đã xử lý xong. Các trường quan trọng:

| Trường | Ý nghĩa | Ví dụ |
|---|---|---|
| `ACTION` | Loại sự kiện | `add`, `remove`, `change`, `bind` |
| `DEVPATH` | Đường dẫn trong `/sys` (bỏ tiền tố `/sys`) | `/devices/platform/…/i2c-1/i2c-dev/i2c-1` |
| `SUBSYSTEM` | Nhóm thiết bị | `i2c-dev`, `block`, `net`, `input`, `backlight` |
| `DEVNAME` | Node trong `/dev`, nếu có | `/dev/i2c-1` |
| `MAJOR`, `MINOR` | Số hiệu thiết bị | `89`, `1` |
| `SEQNUM` | Số thứ tự sự kiện, tăng dần | |

Sau khi udevd xử lý xong, dòng `UDEV` có thêm các biến do rule gán, ví dụ `ID_FS_LABEL=data` cho phân vùng dữ liệu.

## 5. Rule

### 5.1. Vị trí và thứ tự

| Thư mục | Dùng cho |
|---|---|
| `/usr/lib/udev/rules.d/` hoặc `/lib/udev/rules.d/` | Rule đi kèm package. Recipe Yocto cài rule vào đây |
| `/etc/udev/rules.d/` | Rule quản trị viên thêm. File trùng tên sẽ ghi đè file trong `/lib` |
| `/run/udev/rules.d/` | Rule tạm thời, mất khi reboot |

udevd gộp file của cả ba thư mục rồi đọc theo thứ tự tên file. Vì vậy tên file bắt đầu bằng số: rule trong `60-*.rules` chạy sau `50-*.rules` và có thể ghi đè giá trị mà rule trước đã gán.

### 5.2. Cú pháp

Mỗi rule là một dòng gồm nhiều cặp `KEY` + toán tử + `"giá trị"`, cách nhau bằng dấu phẩy. Toán tử chia key thành hai nhóm:

| Toán tử | Nhóm | Ý nghĩa |
|---|---|---|
| `==` | So khớp | Bằng |
| `!=` | So khớp | Khác |
| `=` | Gán | Gán giá trị, ghi đè giá trị cũ |
| `+=` | Gán | Thêm vào danh sách (ví dụ thêm một lệnh `RUN` nữa) |
| `:=` | Gán | Gán và khoá, rule sau không đổi được |

Rule chỉ thực hiện phần gán khi mọi key so khớp trong dòng đều đúng.

Key so khớp hay dùng:

| Key | So với |
|---|---|
| `ACTION` | Loại sự kiện |
| `SUBSYSTEM` | Subsystem của chính thiết bị |
| `KERNEL` | Tên kernel đặt cho thiết bị, ví dụ `i2c-1`, `event0`, `mmcblk0p5` |
| `ATTR{tên}` | Thuộc tính sysfs của chính thiết bị |
| `ATTRS{tên}`, `DRIVERS`, `SUBSYSTEMS` | Thuộc tính, driver, subsystem của thiết bị hoặc bất kỳ thiết bị cha nào của nó |
| `ENV{tên}` | Biến môi trường của sự kiện, kể cả biến do rule trước gán |

Key gán hay dùng:

| Key | Tác dụng |
|---|---|
| `OWNER`, `GROUP`, `MODE` | Owner, group, quyền của node trong `/dev` |
| `SYMLINK` | Tạo thêm symlink trong `/dev` trỏ tới node |
| `ENV{tên}` | Gán biến cho các rule sau hoặc cho systemd dùng |
| `RUN` | Chạy chương trình sau khi xử lý xong sự kiện |
| `TAG+="systemd"` | Báo systemd tạo unit `.device` cho thiết bị |
| `ENV{SYSTEMD_WANTS}` | Khởi động một unit systemd khi thiết bị xuất hiện |

Chuỗi thay thế trong giá trị:

| Chuỗi | Thay bằng |
|---|---|
| `%k` | Tên kernel, ví dụ `i2c-1` |
| `%p` | `DEVPATH`, ví dụ `/devices/platform/backlight/backlight/backlight` |
| `%n` | Số thứ tự kernel, ví dụ `1` của `i2c-1` |

## 6. Rule trong dự án

### 6.1. Cho telemetryd đọc I2C

File `sensornode-core/systemd/60-sensornode-i2c.rules`:

```
SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
```

- `SUBSYSTEM=="i2c-dev"`: áp dụng cho mọi node `/dev/i2c-*`.
- `GROUP="i2c", MODE="0660"`: owner và group `i2c` được đọc và ghi, user khác không được truy cập.

Ở phía service, `sensornode-telemetryd.service` có `User=sensornode`, `SupplementaryGroups=i2c` và `DeviceAllow=char-i2c rw`. Rule và unit phải đi đôi với nhau: thiếu rule thì `/dev/i2c-1` thuộc `root:root` và telemetryd bị `Permission denied`.

### 6.2. Cho UI ghi backlight

File `meta-sensornode/recipes-sensornode/sensornode-ui/files/60-sensornode-backlight.rules`:

```
ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video /sys%p/brightness", RUN+="/bin/chmod g+w /sys%p/brightness"
```

- Backlight không có node trong `/dev`. Nó được điều khiển qua file thuộc tính `brightness` trong `/sys`, nên `GROUP`/`MODE` không áp dụng được. Rule phải dùng `RUN` để tự `chgrp` và `chmod`.
- `/sys%p` ghép thành đường dẫn đầy đủ của thiết bị trong sysfs.
- `sensornode-ui.service` có `SupplementaryGroups=video` nên UI ghi được file này.

## 7. Coldplug và hotplug

- **Hotplug**: thiết bị xuất hiện khi udevd đã chạy, ví dụ cắm USB WiFi lúc hệ thống đang chạy. udevd nhận uevent ngay.
- **Coldplug**: thiết bị đã được kernel phát hiện trong lúc boot, trước khi udevd khởi động. uevent của chúng đã phát ra lúc không có ai nghe, nên bị mất.

Để xử lý coldplug, `systemd-udev-trigger.service` chạy `udevadm trigger`. Lệnh này duyệt `/sys` và yêu cầu kernel phát lại uevent `add` cho mọi thiết bị có sẵn. udevd sau đó xử lý các sự kiện này như thể thiết bị vừa được cắm vào.

```
kernel boot ──► phát hiện SD, eMMC, UART, eth0, I2C… (uevent bị mất)
                    │
systemd-udevd start │
                    ▼
systemd-udev-trigger ──► kernel phát lại uevent cho mọi thiết bị
                    │
                    ▼
udevd xử lý lần lượt ──► từng unit .device chuyển sang active
```

## 8. udev và systemd

Rule mặc định của systemd gắn `TAG+="systemd"` cho các thiết bị quan trọng như ổ đĩa, phân vùng, card mạng, TTY. Khi udevd xử lý xong một thiết bị có tag này, systemd tạo unit `.device` tương ứng và chuyển nó sang active. Một thiết bị có thể có nhiều unit `.device`, mỗi symlink udev tạo ra một unit, ví dụ `dev-mmcblk0p5.device` và `dev-disk-by\x2dlabel-data.device`.

Các unit khác chờ thiết bị thông qua unit `.device`:

- `data.mount` khai báo `What=LABEL=data`. Từ đó systemd tự thêm phụ thuộc vào `dev-disk-by\x2dlabel-data.device`: chỉ mount khi udev đã tạo symlink `/dev/disk/by-label/data`.
- `sensornode-wifi.service` có `BindsTo=sys-subsystem-net-devices-wlan0.device`: chỉ chạy khi có `wlan0` và dừng khi rút USB WiFi.

### Liên quan tới thời gian boot

Trong lần đo boot của dự án (xem `docs/boot-optimize.md`):

- `systemd-udev-trigger` mất khoảng 4.6s. Đây là thời gian phát lại toàn bộ uevent coldplug.
- `dev-mapper-root.device` và `dev-mmcblk0p5.device` đứng đầu `blame` với khoảng 9.5s. Con số này không phải thời gian làm việc, mà là thời gian chờ udevd xử lý tới các thiết bị đó.
- Các phân vùng `mmcblk0p1`–`p5` lần lượt active, cách nhau 0.35–0.65s. Điều này cho thấy udevd đang xử lý chậm từng sự kiện một.

Vì vậy, rule chậm hoặc nhiều thiết bị không cần thiết sẽ kéo dài cả giai đoạn trước `sysinit.target`.

Dự án đã giảm việc của coldplug bằng hai thay đổi:

- Drop-in `20-sensornode-udev-trigger.conf` (recipe `systemd-conf`) bỏ các subsystem không có rule nào cần khỏi lần trigger thiết bị: `dma` (kênh EDMA), `devlink` (liên kết phụ thuộc giữa các thiết bị trong kernel) và `vc` (virtual console):

```ini
[Service]
ExecStart=
ExecStart=-udevadm trigger --type=subsystems --action=add
ExecStart=-udevadm trigger --type=devices --action=add --subsystem-nomatch=dma --subsystem-nomatch=devlink --subsystem-nomatch=vc
```

- Kernel tắt `CONFIG_VT`, nên không còn các thiết bị `tty0`–`tty63`, `vcs*` để phát lại uevent.

Đếm số thiết bị được trigger trên board bằng `--dry-run`:

```sh
root@bbb-sensornode:~# udevadm trigger --dry-run --verbose --type=devices --action=add | grep -c /sys/
443
root@bbb-sensornode:~# udevadm trigger --dry-run --verbose --type=devices --action=add --subsystem-nomatch=dma --subsystem-nomatch=devlink --subsystem-nomatch=vc | grep -c /sys/
272
```

→ Drop-in bỏ được 171 trong 443 thiết bị. Sau hai thay đổi này, `systemd-udev-trigger` không còn nằm trên critical path. Số liệu chi tiết xem lần đo 5 trong `docs/boot-optimize.md`.

Muốn bỏ thêm subsystem nào, kiểm tra trước xem có rule nào khớp với nó không:

```sh
udevadm trigger --dry-run --verbose --type=devices --action=add | grep -c /sys/   # số thiết bị sẽ được trigger
grep -rl 'SUBSYSTEM=="<tên>"' /lib/udev/rules.d /etc/udev/rules.d
```

## 9. Công cụ `udevadm`

| Lệnh | Dùng để |
|---|---|
| `udevadm info -q all -n /dev/i2c-1` | Xem mọi thuộc tính udev của một node: `DEVPATH`, symlink, biến `ENV` |
| `udevadm info -a -n /dev/input/event0` | In thuộc tính sysfs của thiết bị và mọi thiết bị cha, dùng để tìm key so khớp khi viết rule |
| `udevadm monitor --kernel --udev --property` | Theo dõi uevent theo thời gian thực |
| `udevadm test /sys/class/backlight/backlight` | Chạy thử rule trên một thiết bị, in rule nào khớp và sẽ làm gì. Không thực hiện `RUN` |
| `udevadm trigger --action=add /sys/class/backlight/backlight` | Phát lại uevent cho một thiết bị để áp dụng rule mới |
| `udevadm control --reload` | Bắt udevd đọc lại rule sau khi sửa |
| `udevadm settle` | Chờ tới khi udevd xử lý hết hàng đợi sự kiện |
| `udevadm control --log-priority=debug` | Bật log chi tiết, xem bằng `journalctl -u systemd-udevd` |

## 10. Quy trình viết một rule mới

Ví dụ: `sensornode-ui.service` đang ghi cứng `TSLIB_TSDEVICE=/dev/input/event0`. Nếu thêm một thiết bị input khác (bàn phím USB chẳng hạn), số `event` có thể bị đổi. Một symlink ổn định như `/dev/input/touchscreen` sẽ an toàn hơn. Đây là ví dụ minh hoạ, dự án chưa làm.

**Bước 1: Tìm thuộc tính để so khớp.**

```sh
udevadm info -a -n /dev/input/event0
```

Tìm một thuộc tính chỉ màn cảm ứng mới có, thường là `ATTRS{name}` của thiết bị input cha. XPT2046 dùng driver ads7846, nên tên thường có dạng `ADS7846 Touchscreen`. Lấy đúng giá trị in ra trên board, không đoán.

**Bước 2: Viết rule.**

```
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="ADS7846 Touchscreen", SYMLINK+="input/touchscreen"
```

**Bước 3: Test trên board.** Rootfs read-only nhưng `/etc` là overlay ghi được, nên có thể thử nhanh ở đó:

```sh
cp 61-touchscreen.rules /etc/udev/rules.d/
udevadm control --reload
udevadm test /sys/class/input/event0 2>&1 | grep -i symlink
udevadm trigger --action=add /sys/class/input/event0
ls -l /dev/input/touchscreen
```

**Bước 4: Đưa vào image.** Thử xong thì xoá file trong `/etc/udev/rules.d/`, rồi cài rule bằng recipe vào `${nonarch_base_libdir}/udev/rules.d/` giống `60-sensornode-backlight.rules`. Rule để ở `/etc` trên `/data` sẽ không đi theo image và bị mất khi flash lại `.wic`.

## 11. Lưu ý

- Mỗi sự kiện phải xử lý xong nhanh. `RUN` chỉ dùng cho lệnh ngắn như `chmod` hay `chgrp`. udevd kill lệnh chạy quá lâu, và trong lúc chờ thì các sự kiện phụ thuộc bị giữ lại. Việc dài thì giao cho service systemd qua `ENV{SYSTEMD_WANTS}`.
- `GROUP`/`MODE` chỉ áp dụng cho node trong `/dev`. Với file trong `/sys` thì phải dùng `RUN`, như rule backlight.
- `ATTR` chỉ xét chính thiết bị, `ATTRS` xét cả các thiết bị cha. Trong một rule, mọi key `ATTRS`/`DRIVERS`/`SUBSYSTEMS` phải khớp trên **cùng một** thiết bị cha.
- Sửa rule xong phải `udevadm control --reload` rồi `trigger`. Sửa file thôi thì thiết bị đã có không tự áp dụng rule mới.
