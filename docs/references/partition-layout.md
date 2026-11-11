# Partition layout

Bảng tra layout SD card và nội dung partition `/data`.

## Layout

| Vùng | Offset | Kích thước | Kiểu | Mount |
|---|---|---|---|---|
| `MLO` | `0x20000` | — | raw | — |
| `u-boot.img` | `0x60000` | — | raw | — |
| U-Boot env | `0x260000` | `0x20000` | raw | — |
| U-Boot env (backup) | `0x280000` | `0x20000` | raw | — |
| `mmcblk0p1` rootA | 4 MiB | 160 MiB | ext4 | `/` khi `active_slot=A` |
| `mmcblk0p2` rootB | 164 MiB | 160 MiB | ext4 | `/` khi `active_slot=B` |
| `mmcblk0p3` data | 324 MiB | 128 MiB | ext4 | `/data` |

Không có partition `/boot` riêng: kernel nằm trong `/boot` của mỗi slot, trừ khi bật `sensornode-verity`.

## Nội dung slot khi bật `sensornode-verity`

Slot không còn là một ext4 đơn thuần mà là một khối raw (image type `verity`, file `sensornode-image-bbb-sensornode.verity`):

| Vùng | Offset trong slot | Nội dung |
|---|---|---|
| ext4 | 0 | Rootfs, block 4 KiB, không journal, không có `/boot` |
| Hash tree | ngay sau ext4 | dm-verity, sha256, block 4 KiB, không có superblock |
| FIT | `SENSORNODE_SLOT_SIZE_MiB - SENSORNODE_VERITY_FIT_SIZE_MiB` (150 MiB) | Kernel + DTB, config node chứa tham số verity, có chữ ký |

Config node của FIT có các property `sensornode,verity-sectors`, `-data-blocks`, `-hash-start`, `-root-hash`, `-salt`. Chữ ký của config phủ cả các property này. U-Boot đọc chúng bằng `fdt get value` rồi dựng `dm-mod.create`, kernel mount `/dev/dm-0` làm rootfs.

ext4 + hash tree phải kết thúc trước FIT: `IMAGE_ROOTFS_MAXSIZE` giảm còn khoảng `150 MiB × 127/128`, và `do_image_verity` báo lỗi nếu bị chồng.

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

- Offset/size env (offset bản backup tự tính = offset + size), kích thước slot, kích thước `/data`, device của slot A/B và tên file ext4 của `/data` chỉ định nghĩa ở [sensornode-vars.inc](../../meta-sensornode/conf/include/sensornode-vars.inc).
- Script `ota_pick_slot` trong built-in env của U-Boot map `active_slot` → `mmc_part` (A=1, B=2) và dựng `root=/dev/mmcblk0p${mmc_part}`. Nếu đổi `SENSORNODE_SLOT_A_DEV` / `SENSORNODE_SLOT_B_DEV` phải sửa cả patch U-Boot.
- Rootfs ext4 bị giới hạn bởi `IMAGE_ROOTFS_MAXSIZE` = kích thước slot: image vượt quá slot sẽ fail lúc build thay vì fail khi SWUpdate ghi raw.
- Dòng `/data` trong wks phải giữ `--fstype=ext4` và không dùng `--label` với `--source rawcopy`. Dòng rootA của `bbb-sensornode-ab-verity.wks.in` cũng không được có `--label`: rawcopy sẽ chạy `tune2fs -L` và làm sai root hash.
- `SENSORNODE_VERITY_FIT_SIZE_MiB` được build vào env của U-Boot. Đổi giá trị này hoặc bật/tắt `sensornode-verity` đều làm `u-boot.img` cũ không boot được slot mới.
- Mọi thay đổi layout đều không OTA được, phải flash lại SD card.
