# Signing keys

## Generate key

Yocto không tự generate key do `FIT_GENERATE_KEYS = "0"` trong `bbb-common.inc`, ta phải tự generate tay.

Key dev:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 365 \
  -keyout keys/dev/dev.key -out keys/dev/dev.crt \
  -subj "/C=VN/O=SensorNode/OU=Development/CN=SensorNode dev signing key"
chmod 600 keys/dev/dev.key
```

Key production:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 365 \
  -keyout keys/product/product.key -out keys/product/product.crt \
  -subj "/C=VN/O=SensorNode/OU=Production/CN=SensorNode production signing key"
chmod 600 keys/product/product.key
```

Giải thích các tham số:

| Tham số | Vì sao |
|---|---|
| `-newkey rsa:2048` | Match với `FIT_SIGN_ALG = "rsa2048"` trong [`bbb-common.inc`](../meta-sensornode-bsp/conf/machine/include/bbb-common.inc) |
| `-sha256` | Match với `FIT_HASH_ALG = "sha256"` trong [`bbb-common.inc`](../meta-sensornode-bsp/conf/machine/include/bbb-common.inc). |
| `-nodes` | Không đặt passphrase. |
| `-days 365` | Hạn 1 năm. |
| `-x509` | Sinh luôn self-signed cert, không qua CSR. Không có CA nào ở đây: board tin đúng một cert được nhúng sẵn. |

Kiểm tra key và cert là một cặp (hai lệnh phải ra cùng hash) và xem hạn:

```bash
openssl rsa  -in keys/dev/dev.key -noout -modulus | md5sum
openssl x509 -in keys/dev/dev.crt -noout -modulus | md5sum
openssl x509 -in keys/dev/dev.crt -noout -enddate
```

## Key nào commit được

`dev.crt` và `dev.key` commit được vì nó chỉ ký firmware cho board trong phase dev. Commit để mọi máy build ra image dev giống nhau.

`product.crt` commit được vì nó là public và cần nó để build rootfs production trên máy không có quyền ký.

`product.key` không bao giờ commit, ai có file này thì có thể ký được firmware mà mọi thiết bị đã bán sẽ nhận.

> [!CAUTION]
> `product/product.key` trong repo hiện tại được sinh ngay trên máy build và không có passphrase (`mkimage` và `swupdate` không hỏi được passphrase lúc build). Với dự án cá nhân thì chấp nhận được. Với sản phẩm thật, khóa production phải nằm trong HSM hoặc secrets manager, không bao giờ nằm trên máy build và việc ký phải là một bước riêng trong pipeline.

## Đổi key phải flash lại SD card

Public key của U-Boot nằm trong `u-boot.dtb` trên SD card, không cập nhật được qua OTA. Sinh key mới nghĩa là:

1. Board đang chạy vẫn giữ key cũ trong `u-boot.dtb`.
2. `fitImage` ký bằng key mới sẽ không qua verify -> board không boot được slot mới.

Nên đổi key bắt buộc phải flash lại SD card, không thể chuyển bằng OTA. Đây là lý do khóa production phải có hạn dài và được giữ thật cẩn thận: mất nó đồng nghĩa mọi thiết bị đã bán không nhận được update nữa.
