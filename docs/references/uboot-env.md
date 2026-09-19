# U-Boot environment

Bảng tra các biến U-Boot env dùng cho cơ chế A/B.

## Vị trí lưu

| Thuộc tính | Giá trị |
|---|---|
| Thiết bị | `mmcblk0`, raw |
| Offset | `0x260000` |
| Kích thước | `0x20000` |
| Redundant | Không |

Offset/size định nghĩa ở `SENSORNODE_ENV_OFFSET` / `SENSORNODE_ENV_SIZE` trong [sensornode-vars.inc](../../meta-sensornode/conf/include/sensornode-vars.inc).

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
| `fit_image` | `/boot/fitImage` (U-Boot build với `CONFIG_FIT_SIGNATURE`, tức distro feature `sensornode-secureboot`) |
| `kernel_image` | `/boot/zImage` (U-Boot build không có `CONFIG_FIT_SIGNATURE`) |
| `fdtfile` | `/boot/am335x-boneblack.dtb` (U-Boot build không có `CONFIG_FIT_SIGNATURE`) |

## Script

| Script | Việc làm |
|---|---|
| `ota_boot` | Gọi lần lượt `ota_check_rollback` → `ota_pick_slot` → `ota_load_kernel` rồi boot |
| `ota_check_rollback` | `ustate=1`: đủ `boot_limit` thì lật slot và reset, chưa đủ thì tăng `boot_count` |
| `ota_pick_slot` | Map `active_slot` → `mmc_part` |
| `ota_load_kernel` | `ext4load` kernel từ slot active |

## Lệnh userspace

| Lệnh | Tác dụng |
|---|---|
| `fw_printenv active_slot ustate boot_count boot_limit` | Đọc trạng thái |
| `fw_setenv ustate 0` | Sửa thủ công |

Env không được ký — ai ghi được SD card hoặc chạy `fw_setenv` đều sửa được `bootargs` và script boot.
