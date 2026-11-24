# Partition layout

Bảng tra layout SD card và nội dung partition `/data`.

## Layout

Thẻ dùng bảng GPT. Mỗi slot gồm một partition boot (kernel) và một partition rootfs.

| Vùng | Offset | Kích thước | Kiểu | Mount |
|---|---|---|---|---|
| GPT | `0x0` | 17 KiB | — | — |
| `MLO` | `0x20000` | — | raw | — |
| `u-boot.img` | `0x60000` | — | raw | — |
| U-Boot env | `0x260000` | `0x20000` | raw | — |
| U-Boot env (backup) | `0x280000` | `0x20000` | raw | — |
| `mmcblk0p1` bootA | 4 MiB | 16 MiB | ext4 | Không mount, U-Boot `ext4load` |
| `mmcblk0p2` rootA | 20 MiB | 156 MiB | ext4 hoặc ext4 + hash tree | `/` khi `active_slot=A` |
| `mmcblk0p3` bootB | 176 MiB | 16 MiB | ext4 | Không mount, U-Boot `ext4load` |
| `mmcblk0p4` rootB | 192 MiB | 156 MiB | ext4 hoặc ext4 + hash tree | `/` khi `active_slot=B` |
| `mmcblk0p5` data | 348 MiB | 128 MiB | ext4 | `/data` |
| GPT (backup) | | 17 KiB | — | — |

## Nội dung `/data`

| Path | Created | Mô tả |
|---|---|---|
| `config/mqtt.json` | build | Kết nối broker |
| `config/ota.json` | build | Tuỳ chọn OTA |
| `config/setting.json` | build | Tuỳ chọn UI |
| `journal/` | build | System journal persistent |
| `logs/sensors.csv` | runtime | Sensor history |

## Nội dung file `sensors.csv`

| Cột | Kiểu | Ví dụ |
|---|---|---|
| `timestamp` | ISO 8601 | `2026-06-16T10:15:00` |
| `temperature` | float, °C | `27.4` |
| `humidity` | int, %RH | `63` |
| `lux` | int | `312` |

File không có rotation, tăng không giới hạn.

## Journald

| Tham số | Giá trị |
|---|---|
| `Storage` | `persistent` |
| `SyncIntervalSec` | `300` |
| `SystemMaxUse` | `20M` |
| `SystemKeepFree` | `15M` |
| `SystemMaxFileSize` | `4M` |
| `SystemMaxFiles` | `5` |
| `MaxRetentionSec` | `1month` |

`/var/log/journal` là symlink tới `/data/journal`, tạo bởi drop-in của `systemd-journal-flush.service` sau khi `/data` mount.

## Lưu ý khi sửa layout

- Offset/size env (offset bản backup tự tính = offset + size), kích thước partition boot, slot và `/data`, device của boot/rootfs từng slot và tên file ext4 của `/data` chỉ định nghĩa ở [sensornode-vars.inc](../../meta-sensornode/conf/include/sensornode-vars.inc).
- Script `ota_pick_slot` trong built-in env của U-Boot map `active_slot` → `boot_part`/`root_part` (A=1/2, B=3/4) và dựng `root=/dev/mmcblk0p${root_part}`. Nếu đổi `SENSORNODE_BOOT_*_DEV` / `SENSORNODE_SLOT_*_DEV` phải sửa cả patch U-Boot.
- Rootfs ext4 bị giới hạn bởi `IMAGE_ROOTFS_MAXSIZE`: bằng kích thước slot, hoặc khoảng 127/128 slot khi có hash tree. Image vượt quá sẽ fail lúc build thay vì fail khi SWUpdate ghi raw.
- Partition boot/rootfs trong wks không dùng `--label`: với `--source rawcopy`, wic sẽ chạy `tune2fs -L` lên bản sao image, làm đổi nội dung ext4 và hỏng hash verity. Vì vậy các partition GPT không có tên.
- Dòng `/data` trong wks phải giữ `--fstype=ext4` và không dùng `--label` với `--source rawcopy`.
- Mọi thay đổi layout đều không OTA được, phải flash lại SD card.
