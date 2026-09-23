# CR-0001: Move signing keys out of the build directory

Commit: `6148118`

## Vấn đề

`UBOOT_SIGN_KEYDIR ?= "${TOPDIR}/keys"` trỏ vào build directory và `FIT_GENERATE_KEYS = "1"` cho phép Yocto tự sinh key khi chưa có. Nếu xóa build directory, đổi máy build hoặc chạy CI trên runner sạch thì đều sinh một cặp key RSA mới, trong khi thiết bị đang chạy U-Boot vẫn giữ public key cũ. Do đó, gói `.swu` được ký bằng key mới sẽ bị từ chối ở cả tầng FIT signature lẫn tầng CMS. Nói cách khác, khả năng OTA của thiết bị đang phụ thuộc vào việc giữ nguyên một thư mục build trên một máy cụ thể. 

## Mô tả thay đổi

Tạo thư mục `keys/` nằm ở gốc repo, với:
- `keys/dev` chứa key cho develop, key này có thể được push lên git, bất kỳ ai cũng có thể sử dụng.
- `keys/product` chứa key cho produc, key này không được push lên git. **Cần được sao lưu ở nơi an toàn, tách khỏi máy build.**

Sau đó tuỳ vào việc build cho dev hay product mà trỏ `UBOOT_SIGN_KEYDIR` tới thư mục tương ứng.

Ngoài ra, đặt `FIT_GENERATE_KEYS = "0"` để không tự sinh key khi chưa có.

## Kiểm chứng

Kiểm tra đường dẫn key theo từng distro trên máy build:

```bash
DISTRO=sensornode-dev bitbake -e u-boot | grep -E '^UBOOT_SIGN_(KEYDIR|KEYNAME)='   # <repo>/keys/dev, dev
DISTRO=sensornode     bitbake -e u-boot | grep -E '^UBOOT_SIGN_(KEYDIR|KEYNAME)='   # <repo>/keys/product, product
```

Check đầy đủ cần chạy trên board: build `sensornode-image-swu` ở một build directory sạch với cùng key, cài lên thiết bị đang chạy bản cũ, gói phải được chấp nhận.
