# CR-0004: restrict stored U-Boot environment to A/B state

Commit: `730edd4`

## Vấn đề

Bản production bật verified boot, U-Boot chỉ boot `fitImage` có chữ ký. Nhưng lệnh boot (`bootcmd`, `ota_boot`, `bootargs`) lại nằm trong env trên thẻ SD, ai có root trên Linux hoặc cầm được thẻ đều sửa được:

Hiện tại, các script boot (`bootcmd`, `ota_boot`, `bootargs`) nằm trong env trên thẻ SD mà env lại chưa có cơ chế bảo vệ. Do đó, ai có quyền root trên Linux hoặc cầm được thẻ thì đều có thể sửa được các lệnh boot:


```bash
fw_setenv bootcmd "echo pwned"
fw_setenv ota_boot "setenv bootargs root=/dev/mmcblk0p1 rw init=/bin/sh; run ota_load_kernel; bootm \${kernel_addr_r}"
fw_printenv bootcmd ota_boot
```

```
bootcmd=echo pwned
ota_boot=setenv bootargs root=/dev/mmcblk0p1 rw init=/bin/sh; run ota_load_kernel; bootm ${kernel_addr_r}
```

→ Kernel vẫn là kernel đã sign nhưng boot với `rw init=/bin/sh` thì verified boot không còn ý nghĩa.

Yêu cầu: U-Boot chỉ được phép ghi 3 biến trạng thái A/B mà luồng OTA cần ghi (`active_slot`, `ustate`, `boot_count`). Mọi biến khác phải lấy từ env mặc định nằm trong `u-boot.img` đã sign.

## Thiết kế

Lúc boot, U-Boot nạp env theo thứ tự các bước:
1. Driver `nowhere` nạp env mặc định build trong `u-boot.img`. File này đã được sign và kiểm tra ở tầng dưới.
2. Driver MMC nạp env trên thẻ. Chỉ các biến có cờ `w` được ghi đè lên env mặc định, các biến khác bị bỏ qua.
3. `saveenv` vẫn ghi toàn bộ env xuống thẻ như cũ.

Mặc định U-Boot gọi driver MMC trước `nowhere` (`env/env.c`). Vì vậy board phải override `env_get_location()` để đổi thứ tự: nạp `nowhere` trước rồi mới tới MMC, còn lưu thì luôn ghi vào MMC

Danh sách biến có thể ghi được khai báo trong `am335x_evm.h`:

```c
#define CONFIG_ENV_FLAGS_LIST_STATIC \
	"active_slot:sw,ustate:sw,boot_count:sw"
```

Trong đó: `s` là kiểu chuỗi, `w` là được ghi đè từ thẻ. Dùng `s` chứ không dùng `d` (số thập phân) vì `setexpr` tăng `boot_count` ghi ra số hex.

## Cách dùng

- Bật bằng distro feature `sensornode-secureboot`. Build không có feature này thì U-Boot vẫn nạp toàn bộ env như trước.
- Phải flash lại toàn bộ thẻ SD vì U-Boot không cập nhật qua OTA.
- `fw_setenv` với biến ngoài danh sách (vd `bootdelay`, `bootargs`) vẫn ghi xuống thẻ và `fw_printenv` vẫn thấy nhưng U-Boot bỏ qua. Muốn đổi thì sửa env mặc định trong patch U-Boot rồi build lại.
- Thêm biến trạng thái mới thì cần thêm `<tên>:sw` vào `CONFIG_ENV_FLAGS_LIST_STATIC`.

## Kiểm chứng

Cần flash lại toàn bộ thẻ SD, sau đó:

1. Log boot có `Loading Environment from nowhere... OK` rồi `Loading Environment from MMC... OK`, board boot lên `login:`.
2. `fw_setenv bootcmd "echo pwned"` rồi reboot. Cần board vẫn boot bình thường, tại prompt U-Boot `printenv bootcmd` in `bootcmd=run ota_boot`.
3. `fw_setenv ustate 1 && reboot`. Cần log có `OTA: upgrade boot attempt 1/3`, tức 3 biến trạng thái vẫn được nạp từ thẻ.
4. Sau một lần OTA sang slot B: `fw_setenv ustate 1`, `fw_setenv boot_count 3`, reboot. Cần rollback về slot A.
