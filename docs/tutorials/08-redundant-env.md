# U-Boot env backup

## 1. Cấu trúc một bản env

```
Không redundant:                Redundant:
+--------+-------------+        +--------+------+-------------+
| CRC 4B | data ...    |        | CRC 4B | cờ 1B| data ...    |
+--------+-------------+        +--------+------+-------------+
```

- **CRC**: checksum của phần data. Nếu data bị ghi dở thì CRC không match và U-Boot biết bản đó hỏng.
- **Cờ**: số đếm (0–255), tăng thêm 1 mỗi lần lưu. Bản có cờ lớn hơn là bản mới hơn.
- **data**: các chuỗi `name=value` nối nhau bằng `\0`.

Vì header có thêm 1 byte cờ nên data bị lệch đi 1 byte. Đó cũng là lý do U-Boot cũ không đọc được env mới.

Trên thẻ SD:

| Bản | Offset | Kích thước |
|---|---|---|
| Chính | `0x260000` | `0x20000` |
| Backup | `0x280000` | `0x20000` |

## 2. Khi đọc: chọn bản nào?

U-Boot đọc cả hai bản rồi chọn một bản (`env_check_redund` trong `env/common.c`):

| Bản chính | Bản backup | Kết quả |
|---|---|---|
| CRC đúng | CRC sai | Dùng bản chính |
| CRC sai | CRC đúng | Dùng bản backup |
| CRC đúng | CRC đúng | Dùng bản có cờ lớn hơn |
| CRC sai | CRC sai | Env mặc định, in `bad CRC` |

## 3. Khi ghi: ghi vào đâu?

Mỗi lần `saveenv` hoặc `fw_setenv`:

1. Tăng cờ: `flags = cờ của bản đang dùng + 1`.
2. Ghi vào bản không dùng, tức bản cũ hơn.
3. Ghi xong mới coi bản vừa ghi là bản đang dùng.

Ví dụ qua ba lần lưu liên tiếp:

```
                  bản chính (0x260000)   bản backup (0x280000)
Sau khi flash     cờ=1, data X           cờ=1, data X  → cờ bằng nhau, dùng bản chính
saveenv (Y)       cờ=1, data X           cờ=2, data Y  ← ghi bản backup
saveenv (Z)       cờ=3, data Z  ←        cờ=2, data Y    ghi bản chính
saveenv (W)       cờ=3, data Z           cờ=4, data W  ← ghi bản backup
```

Dòng `Writing to redundant MMC(0)... OK` và `Writing to MMC(0)... OK` luân phiên nhau trong log U-Boot.

Khi cờ tăng từ 255 lên 0 thì U-Boot coi 0 là mới hơn 255, nên không bị lỗi tràn số.

## 4. Mất điện giữa lúc ghi

Giả sử đang ở trạng thái Z (bản chính, cờ 3) và đang ghi W vào bản backup thì mất điện:

```
bản chính    cờ=3, data Z    → CRC đúng
bản backup   ghi dở          → CRC sai
```

Lần boot sau, bản backup bị loại vì sai CRC. U-Boot dùng Z, tức trạng thái ngay trước lần ghi hỏng. Chỉ mất thay đổi cuối cùng, không bao giờ mất toàn bộ env. Lần lưu kế tiếp sẽ ghi đè lên chính bản hỏng và hai bản lại đều hợp lệ.

Áp dụng vào A/B OTA, ví dụ đang chạy slot B và `ota_check_rollback` đang `saveenv` để tăng `boot_count` thì mất điện. U-Boot quay về bản trước đó, vẫn `active_slot=B`. Chỉ `boot_count` chưa được tăng và lần boot này sẽ tăng lại.

## 5. Giới hạn

- Chỉ chống được việc ghi dở (mất điện, reset giữa lúc ghi). Nếu ghi một giá trị sai mà CRC vẫn đúng, ví dụ `fw_setenv active_slot X` thì bản đó vẫn hợp lệ và được dùng.
- Nếu cả hai vùng cùng hỏng (thẻ lỗi hoặc bị ghi đè cả hai) thì U-Boot vẫn quay về env mặc định.
- Env không được ký nên ai ghi được thẻ vẫn sửa được env.
