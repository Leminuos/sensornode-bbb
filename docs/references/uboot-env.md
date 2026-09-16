# U-Boot environment

Bảng tra các biến U-Boot env dùng cho cơ chế A/B.

## Vị trí lưu

| Thuộc tính | Giá trị |
|---|---|
| Thiết bị | `mmcblk0`, raw |
| Offset | `0x260000` |
| Kích thước | `0x20000` |
| Redundant | Không |

Offset/size trong `0001-bbb-ota.cfg` (U-Boot) và `fw_env.config` (userspace) phải khớp nhau. Khi CRC env trên MMC sai, U-Boot dùng built-in env.

## Biến trạng thái

| Biến | Giá trị | Mặc định | Ai ghi |
|---|---|---|---|
| `active_slot` | `A`, `B` | `A` | `switch-slot.sh`, U-Boot khi rollback |
| `ustate` | `0` stable, `1` đang thử | `0` | `switch-slot.sh` → `1`, `ota-confirm-boot.sh` / U-Boot rollback → `0` |
| `boot_count` | ≥ 0 | `0` | U-Boot tăng mỗi boot khi `ustate=1`, reset khi flash / commit / rollback |
| `boot_limit` | > 0 | `3` | Không đổi lúc runtime |

## Biến boot

| Biến | Giá trị |
|---|---|
| `bootcmd` | `run ota_boot` |
| `mmc_part` | `1` (slot A), `2` (slot B) |
| `bootargs` | `root=/dev/mmcblk0p${mmc_part} ro rootwait console=ttyO0,115200n8 panic=10` |
| `fit_image` | `/boot/fitImage` (secure-boot) |
| `kernel_image` | `/boot/zImage` (normal boot) |
| `fdtfile` | `/boot/am335x-boneblack.dtb` (normal boot) |

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
