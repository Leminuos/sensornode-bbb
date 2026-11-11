# U-Boot environment

Bảng tra các biến U-Boot env dùng cho cơ chế A/B.

## Vị trí lưu

| Thuộc tính | Giá trị |
|---|---|
| Thiết bị | `mmcblk0`, raw |
| Offset | `0x260000` (bản chính), `0x280000` (bản backup) |
| Kích thước | `0x20000` |
| Redundant | Có — hai bản, mỗi lần `saveenv`/`fw_setenv` ghi vào bản cũ hơn rồi đổi cờ, mất điện giữa chừng vẫn còn bản kia |

Offset/size định nghĩa ở `SENSORNODE_ENV_OFFSET` / `SENSORNODE_ENV_SIZE` trong [sensornode-vars.inc](../../meta-sensornode/conf/include/sensornode-vars.inc). Offset bản backup `SENSORNODE_ENV_OFFSET_REDUND` = offset + size, tự tính, không khai tay.

## Biến trạng thái

| Biến | Giá trị | Mặc định | Ai ghi |
|---|---|---|---|
| `active_slot` | `A`, `B` | `A` | SWUpdate `bootenv` của install set, U-Boot khi rollback |
| `ustate` | `0` stable, `1` đang thử | `0` | SWUpdate `bootenv` → `1`, `ota-confirm-boot.sh` / U-Boot rollback → `0` |
| `boot_count` | ≥ 0 | `0` | U-Boot tăng mỗi boot khi `ustate=1`, reset khi flash / commit / rollback |
| `boot_limit` | > 0 | `3` | Không đổi lúc runtime |

## Biến boot

| Biến | Giá trị |
|---|---|
| `bootcmd` | `run ota_boot` |
| `mmc_part` | `1` (slot A), `2` (slot B) |
| `bootargs` | `root=/dev/mmcblk0p${mmc_part} ro rootwait console=ttyO0,115200n8 panic=10` |
| `bootargs` (`sensornode-verity`) | `root=/dev/dm-0 dm-mod.waitfor=/dev/mmcblk0p${mmc_part} dm-mod.create="vroot,,,ro,0 <sectors> verity 1 <slot> <slot> 4096 4096 <data_blocks> <hash_start> sha256 <root_hash> <salt>"`, tham số lấy từ FIT |
| `verity_*` (`sensornode-verity`) | Biến tạm, `ota_load_kernel` đọc từ config node của FIT |
| `fit_image` | `/boot/fitImage` (U-Boot build với `CONFIG_FIT_SIGNATURE`, tức distro feature `sensornode-secureboot`) |
| `kernel_image` | `/boot/zImage` (U-Boot build không có `CONFIG_FIT_SIGNATURE`) |
| `fdtfile` | `/boot/am335x-boneblack.dtb` (U-Boot build không có `CONFIG_FIT_SIGNATURE`) |

## Script

| Script | Việc làm |
|---|---|
| `ota_boot` | Gọi lần lượt `ota_check_rollback` → `ota_pick_slot` → `ota_load_kernel`, đặt `bootargs` rồi boot |
| `ota_check_rollback` | `ustate=1`: đủ `boot_limit` thì lật slot và reset, chưa đủ thì tăng `boot_count` |
| `ota_pick_slot` | Map `active_slot` → `mmc_part` |
| `ota_load_kernel` | `ext4load` kernel từ slot active. Với `sensornode-verity`: `part start` + `mmc read` FIT ở đuôi slot, rồi `fdt get value` các tham số verity |

## Lệnh userspace

| Lệnh | Tác dụng |
|---|---|
| `fw_printenv active_slot ustate boot_count boot_limit` | Đọc trạng thái |
| `fw_setenv ustate 0` | Sửa thủ công |

## Biến được nạp từ thẻ

Env không được ký — ai ghi được SD card hoặc chạy `fw_setenv` đều sửa được nội dung env trên thẻ. Mức ảnh hưởng tuỳ distro feature:

| Build | U-Boot nạp gì từ env trên thẻ |
|---|---|
| Không có `sensornode-secureboot` | Toàn bộ — sửa được `bootargs`, `bootcmd`, script boot |
| Có `sensornode-secureboot` | Chỉ `active_slot`, `ustate`, `boot_count`; mọi biến khác lấy từ env mặc định build trong `u-boot.img` |

Với `sensornode-secureboot`, U-Boot nạp env mặc định trước (driver `nowhere`), rồi env trên MMC chỉ ghi đè các biến có cờ `w` trong `CONFIG_ENV_FLAGS_LIST_STATIC` (`CONFIG_ENV_APPEND` + `CONFIG_ENV_WRITEABLE_LIST`). `saveenv` vẫn ghi toàn bộ env xuống MMC. Hệ quả: `fw_setenv` một biến ngoài danh sách (vd `bootdelay`, `bootargs`) vẫn ghi được xuống thẻ và `fw_printenv` vẫn thấy, nhưng U-Boot bỏ qua. Muốn thêm biến trạng thái mới phải thêm vào danh sách trong `0002-bbb-env-writeable-list.patch`.
