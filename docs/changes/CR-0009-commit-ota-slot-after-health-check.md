# CR-0009: commit OTA slot only after health check

Commit: `e2b9ba0`

## Vấn đề

Nếu OTA một bản mà ứng dụng crash liên tục hoặc không đọc được cảm biến hoặc `/data` không ghi được thì slot mới vẫn được commit và không rollback về slot cũ. Rollback A/B hiện chỉ cứu được trường hợp kernel không boot nổi.

## Nguyên nhân

Service `ota-confirm-boot.service` đang định nghĩa như sau:

```
After=local-fs.target
Before=multi-user.target
```

Nghĩa là service chạy ngay sau khi filesystem mount và trước `multi-user.target` → slot mới được commit trước khi `sensornode-ui.service` được khởi động (app nằm trong `multi-user.target`).

Trong khi đó, script chỉ kiểm tra `ustate` rồi xoá cờ, không kiểm tra gì về trạng thái hệ thống:

```sh
if [ "${usate}" = "1" ]; then
    "${FW_SETENV}" boot_count "0"
    "${FW_SETENV}" ustate     "0"
fi
```

## Giải pháp

Biến bước commit thành health check, tức là chỉ commit khi thiết bị làm đúng chức năng, nếu không thì reboot mà không commit để U-Boot tự rollback.

Luồng mới khi boot thử một slot vừa OTA (`ustate=1`):

```
U-Boot: boot_count += 1 → boot slot mới
  └─ systemd khởi động sensornode-ui.service
       └─ ota-confirm-boot.service chạy health check (tối đa 120s)
            ├─ đạt   → boot_count=0, ustate=0 (commit)
            └─ không → reboot → U-Boot đếm tiếp → đủ 3 lần thì quay về slot cũ
```

### 1. Chạy health check sau khi app đã khởi động

```ini
[Unit]
After=local-fs.target sensornode-ui.service
ConditionPathExists=/usr/bin/fw_setenv

[Service]
Type=simple
ExecStart=/usr/bin/ota-confirm-boot.sh
RemainAfterExit=yes
```

- Bỏ `Before=multi-user.target` và thêm `After=sensornode-ui.service` để script chỉ chạy khi app đã được start.
- Đổi `Type=oneshot` thành `Type=simple` để boot không bị chặn trong lúc chờ health check.

### 2. Script health check

- `ustate=0` (slot đã ổn định) → thoát ngay, không kiểm tra, không bao giờ reboot.
- `ustate=1` (đang thử) → cứ 5 giây kiểm tra một lần, tối đa 120 giây. Phải đạt cả 4 điều kiện trong cùng một lượt:

| Điều kiện | Cách kiểm tra |
|---|---|
| `/data` dùng được | Đã mount và ghi rồi xoá thử được một file thành công |
| App chạy ổn định | `sensornode-ui` ở trạng thái `active` và đã active liên tục ≥ 30 giây. |
| Cảm biến đọc được | Đọc được giá trị hợp lệ từ SHT30 và BH1750 |

- Đạt thì ghi `boot_count=0`, `ustate=0` như cũ.
- Hết 120 giây mà chưa đạt thì ghi lý do fail cuối cùng vào journal rồi `systemctl --no-block reboot`.

Điều kiện "active liên tục ≥ 30 giây" dùng để bắt app crash lặp: giữa hai lần restart, app vẫn có lúc ở trạng thái `active`, nên chỉ kiểm tra `is-active` một lần là chưa đủ. Script so `ActiveEnterTimestampMonotonic` của service với `/proc/uptime` để biết app đã chạy được bao lâu.

### 3. Giới hạn restart của app

`sensornode-ui.service` thêm:

```ini
StartLimitIntervalSec=60
StartLimitBurst=5
```

App crash 5 lần trong 60 giây thì systemd dừng restart và đưa service về `failed` → health check sẽ thấy lỗi ngay. Điều này giúp crash loop trở thành tín hiệu rollback thay vì restart vô hạn.

> [!NOTE]
> Các giới hạn cần biết:
>
> - Broker chạy trên máy host nên host tắt đúng lúc OTA sẽ làm một firmware tốt bị rollback không cần thiết.
> - Cảm biến hỏng đúng lúc OTA thì bản tốt cũng bị rollback.

## Kiểm chứng trên board

Cài một `.swu` bình thường, chờ khoảng 30–40 giây kể từ khi app start:

```bash
journalctl -b -u ota-confirm-boot     # Health check passed, slot X committed
fw_printenv ustate boot_count         # ustate=0, boot_count=0
systemctl is-system-running           # running, không bị chặn bởi ota-confirm-boot
```

Build một `.swu` có app lỗi bằng cách thêm vào `local.conf`:

```bitbake
broken_app() {
    sed -i 's|^ExecStart=.*|ExecStart=/bin/false|' ${IMAGE_ROOTFS}/lib/systemd/system/sensornode-ui.service
}
ROOTFS_POSTPROCESS_COMMAND:append:pn-sensornode-image = " broken_app; "
```

Cài bản này rồi theo dõi serial console. Cần thấy `OTA: upgrade boot attempt 1/3`, `2/3`, `3/3`, mỗi lần cách nhau khoảng 2 phút, sau đó là `rolling back`.

Sau rollback:

```bash
fw_printenv active_slot ustate boot_count   # slot cũ, ustate=0, boot_count=0
journalctl -b -1 -u ota-confirm-boot        # Health check failed: sensornode-ui.service is failed ...
```

Làm lại tương tự với cảm biến bị rút ra: phải rollback. Cắm lại cảm biến và cài lại thì phải commit.
