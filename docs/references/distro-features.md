# Distro variants và distro features

Bảng tra các distro của SensorNode, các `DISTRO_FEATURES` riêng của dự án, mỗi feature bật những gì và được tiêu thụ ở đâu.

## Nguyên tắc

Build development và production chỉ khác nhau ở distro. Mỗi distro bật một tập feature `sensornode-*`. Các recipe, image, machine conf đọc feature bằng `bb.utils.contains('DISTRO_FEATURES', ...)`.

Mọi feature của dự án có tiền tố `sensornode-` để không trùng với feature của upstream (poky, meta-openembedded, meta-swupdate).

## Chọn distro khi build

Distro mặc định đặt trong `conf/local.conf`:

```bitbake
MACHINE = "bbb-sensornode"
DISTRO ?= "sensornode-dev"
```

Build distro khác mà không sửa `local.conf`:

```bash
DISTRO=sensornode bitbake sensornode-image sensornode-image-swu
```

Mỗi distro có `TMPDIR = ${TOPDIR}/tmp-${DISTRO}` nên artifact nằm ở `tmp-sensornode-dev/deploy/images/bbb-sensornode/` hoặc `tmp-sensornode/deploy/images/bbb-sensornode/`. Hai build cùng tồn tại trong một build directory và không ghi đè nhau. `sstate-cache` và `downloads` vẫn dùng chung.

## Distro features

| Feature | Nội dung |
|---|---|
| `sensornode-hmi` | Qt HMI trên màn TFT SPI + touch |
| `sensornode-ota` | SWUpdate, layout A/B, U-Boot A/B env, verify boot + rollback |
| `sensornode-secureboot` | U-Boot verified boot + `.swu` ký CMS |
| `sensornode-readonly` | Rootfs mount read-only |
| `sensornode-devtools` | Dev tools (`i2c-tools`, `evtest`, `strace`, `tslib-calibrate`...) |
| `sensornode-login` | Login access (`debug-tweaks`, `ssh-server-openssh`) |
| `sensornode-debug` | Bật log Qt app |

## Thêm feature mới

1. Đặt tên có tiền tố `sensornode-`.
2. Tiêu thụ bằng `bb.utils.contains('DISTRO_FEATURES', 'sensornode-<tên>', ..., d)` ở recipe/conf liên quan.
3. Bật feature trong `sensornode-dev.conf` và/hoặc `sensornode.conf`, hoặc trong `sensornode-base.inc` nếu cả hai cùng dùng.
4. Nếu feature phụ thuộc feature khác, thêm kiểm tra vào khối `python ()` trong `sensornode-image-common.inc`.
5. Cập nhật file này và bảng build config trong `README.md`.
