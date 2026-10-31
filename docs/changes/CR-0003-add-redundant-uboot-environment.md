# CR-0003: add redundant U-Boot environment

Commit: `ae3da99`

## Vấn đề

Hiện tại, trên thẻ chỉ có một bản env duy nhất tại offset `0x260000`, trong khi trạng thái A/B được ghi lại nhiều lần: SWUpdate ghi khi cài `.swu`, `ota_check_rollback` ghi ở mỗi lần boot thử, `ota-confirm-boot` ghi khi commit.

Nếu mất điện xảy ra đúng lúc đang ghi thì sẽ làm hỏng CRC của vùng env. Khi đó, U-Boot quay về env mặc định nên một thiết bị đang chạy slot B sẽ nhảy ngược về slot A và mất toàn bộ trạng thái A/B.

## Thiết kế

Thêm một env backup vào U-Boot: Mỗi lần lưu chỉ ghi đè bản cũ hơn, không ghi bản đang dùng, nên mất điện giữa chừng chỉ làm mất thay đổi cuối cùng.

Mỗi bản có thêm 1 byte cờ ngay sau CRC, tăng 1 sau mỗi lần lưu. Lúc đọc, U-Boot và libubootenv sẽ bỏ bản CRC sai. Nếu cả hai đều đúng thì chọn bản có cờ lớn hơn.

| Bản | Offset | Kích thước |
|---|---|---|
| Main | `0x260000` | `0x20000` |
| Backup | `0x280000` | `0x20000` |

Tính năng chỉ có hiệu lực sau khi flash lại toàn bộ thẻ SD. Không cài qua OTA được: `.swu` chỉ chứa rootfs, không chứa U-Boot. Nếu cài rootfs mới (có `fw_env.config` hai dòng) lên thiết bị đang chạy U-Boot cũ, libubootenv sẽ ghi env có byte cờ, U-Boot cũ đọc lệch 1 byte, CRC sai và quay về env mặc định.

> [!NOTE]
> Thay đổi này không cài qua OTA được. `.swu` chỉ chứa rootfs, không chứa U-Boot. Nếu cài rootfs mới lên thiết bị đang chạy U-Boot cũ, libubootenv sẽ ghi env có byte cờ. U-Boot cũ đọc lệch 1 byte, CRC sai, quay về env mặc định. Thiết bị phải flash lại toàn bộ thẻ SD.

## Kiểm chứng

Flash lại toàn bộ thẻ SD, sau đó:
1. Log UART lúc boot không có `*** Warning - bad CRC, using default environment`.
2. `fw_setenv ustate 1 && reboot`: log U-Boot có `OTA: upgrade boot attempt 1/3` và `Writing to redundant MMC(0)... OK` hoặc `Writing to MMC(0)... OK`.
3. Cho `fw_setenv` chạy liên tục trong vòng lặp và rút nguồn ngẫu nhiên 10–20 lần. Sau mỗi lần: không có `bad CRC`, `active_slot` không đổi.
