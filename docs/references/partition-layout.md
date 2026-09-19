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

- Offset/size env, kích thước slot, kích thước `/data`, device của slot A/B và tên file ext4 của `/data` chỉ định nghĩa ở [sensornode-vars.inc](../../meta-sensornode/conf/include/sensornode-vars.inc).
- Script `ota_pick_slot` trong built-in env của U-Boot map `active_slot` → `mmc_part` (A=1, B=2) và dựng `root=/dev/mmcblk0p${mmc_part}`. Nếu đổi `SENSORNODE_SLOT_A_DEV` / `SENSORNODE_SLOT_B_DEV` phải sửa cả patch U-Boot.
- Rootfs ext4 bị giới hạn bởi `IMAGE_ROOTFS_MAXSIZE` = kích thước slot: image vượt quá slot sẽ fail lúc build thay vì fail khi SWUpdate ghi raw.
- Dòng `/data` trong wks phải giữ `--fstype=ext4` và không dùng `--label` với `--source rawcopy`.
- Mọi thay đổi layout đều không OTA được, phải flash lại SD card.
