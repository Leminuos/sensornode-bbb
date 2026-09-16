# Partition layout

Bảng tra layout SD card và nội dung partition `/data`.

## Layout

| Vùng | Offset | Kích thước | Kiểu | Mount |
|---|---|---|---|---|
| `MLO` | `0x20000` | — | raw | — |
| `u-boot.img` | `0x60000` | — | raw | — |
| U-Boot env | `0x260000` | `0x20000` | raw | — |
| `mmcblk0p1` rootA | 4 MiB | 160 MiB | ext4 | `/` khi `active_slot=A` |
| `mmcblk0p2` rootB | 164 MiB | 160 MiB | ext4 | `/` khi `active_slot=B` |
| `mmcblk0p3` data | 324 MiB | 128 MiB | ext4 | `/data` |

Không có partition `/boot` riêng: kernel nằm trong `/boot` của mỗi slot.

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

`/var/log/journal` là symlink tới `/data/journal`, tạo bởi `journald-data-flush.service` sau khi `/data` mount.

## Lưu ý khi sửa layout

- Đổi offset/size env phải sửa đồng bộ `0001-bbb-ota.cfg`, `fw_env.config` và `mkenvimage -s`.
- Đổi kích thước `/data` phải sửa cả `--fixed-size` trong wks và `DATA_PARTITION_SIZE_KiB` trong `data-partition.bb`.
- Dòng `/data` trong wks phải giữ `--fstype=ext4` và không dùng `--label` với `--source rawcopy`.
- Mọi thay đổi layout đều không OTA được, phải flash lại SD card.
