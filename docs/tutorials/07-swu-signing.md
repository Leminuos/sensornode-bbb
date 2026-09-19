# Sign gói `.swu` và verify lúc chạy

Bản production chỉ chấp nhận gói cập nhật do đúng máy build của dự án tạo ra. Cơ chế gồm hai phần bổ trợ nhau: CMS signature trên phần mô tả gói và hash SHA-256 cho từng file dữ liệu bên trong. Tutorial này đi từ lúc Yocto sign gói, tới lúc SWUpdate trên thiết bị kiểm tra và từ chối gói không hợp lệ.

Đọc tài liệu này giúp ta hiểu:

- Mô hình tin cậy: sign cái gì, hash cái gì và vì sao chỉ cần sign một file.
- Feature `sensornode-secureboot` bật những gì ở phía build và phía thiết bị.
- Thứ tự SWUpdate kiểm tra lúc chạy và mỗi bước hỏng thì chuyện gì xảy ra.
- Cách tự kiểm chứng trên máy build và trên board.
- Quản lý key

## 1. Mô hình tin cậy

Một gói `.swu` là một file nén dạng archive cpio gồm ba loại thành phần:

| Thành phần | Nội dung |
|---|---|---|
| `sw-description` | Mô tả gói: version, board, install set, thiết bị đích và hash của từng file dữ liệu |
| `sw-description.sig` | CMS signature (DER) của file trên |
| `sensornode-image-...ext4.gz` | Rootfs sẽ ghi vào slot |

Chỉ `sw-description` được sign vì nó chứa hash của mọi file còn lại:

- Sửa rootfs trong gói → hash không match giá trị được khai báo trong `sw-description` → blocked.
- Sửa giá trị hash trong `sw-description` → signature không còn đúng → blocked.

Cặp khoá dùng để sign chính là cặp khoá của verified boot (`UBOOT_SIGN_KEYDIR`/`UBOOT_SIGN_KEYNAME`) nên thiết bị chỉ có một root tin cậy duy nhất cho cả kernel lẫn gói cập nhật.

Phạm vi bảo vệ: signature chứng minh gói do người giữ khoá tạo ra và không bị sửa trên đường truyền. Nó không chống việc cài lại một gói cũ hợp lệ và không bảo vệ rootfs sau khi đã ghi lên thẻ.

## 2. Recipe tạo gói signed

### 2.1. Khai báo

Trong `sensornode-image-swu.bb`:

```bitbake
SWUPDATE_SIGNING = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'CMS', '', d)}"
SWUPDATE_CMS_KEY  = "${UBOOT_SIGN_KEYDIR}/${UBOOT_SIGN_KEYNAME}.key"
SWUPDATE_CMS_CERT = "${UBOOT_SIGN_KEYDIR}/${UBOOT_SIGN_KEYNAME}.crt"
```

| Biến | Vai trò |
|---|---|
| `SWUPDATE_SIGNING` | Chọn cơ chế sign. Class hỗ trợ gồm: `RSA`, `CMS`, `CUSTOM`. Giá trị rỗng nghĩa là không sign nên bản dev tự động bỏ qua toàn bộ bước này |
| `SWUPDATE_CMS_KEY` | Private key sign gói |
| `SWUPDATE_CMS_CERT` | Certificate của người ký, được nhúng kèm vào cấu trúc CMS |

Hai đường dẫn key không hardcode mà suy ra từ `UBOOT_SIGN_KEYDIR` và `UBOOT_SIGN_KEYNAME` của verified boot. Nhờ vậy đổi chỗ để khoá chỉ cần sửa machine conf và không thể xảy ra tình trạng kernel ký bằng khoá này còn gói OTA ký bằng khoá khác.

### 2.2. Class làm gì trong `do_swuimage`

| Thứ tự | Việc làm |
|---|---|
| 1 | Chạy `do_render_swdesc` của recipe: thay các `@...@` bằng giá trị từ `sensornode-vars.inc` |
| 2 | Duyệt `sw-description`: thay mỗi lời gọi `$swupdate_get_sha256(<file>)` bằng SHA-256 của file đó |
| 3 | Nếu `SWUPDATE_SIGNING = "CMS"`: ký `sw-description`, ghi ra `sw-description.sig` |
| 4 | Đóng cpio theo thứ tự: `sw-description`, `sw-description.sig`, rồi các file dữ liệu |

Thứ tự 2 trước 3 là điều làm cho mô hình tin cậy ở mục 1 hoạt động: hash được tính và ghi vào `sw-description` trước, chữ ký phủ lên kết quả đó.

Lệnh sign mà class chạy ở bước 3 (rút gọn từ `swupdate-common.bbclass`):

```bash
openssl cms -sign -in sw-description -out sw-description.sig \
    -signer keys/dev.crt -inkey keys/dev.key \
    -outform DER -nosmimecap -binary
```

| Tuỳ chọn | Ý nghĩa |
|---|---|
| `-outform DER` | Chữ ký ở dạng nhị phân DER, không phải PEM |
| `-binary` | Không biến đổi ký tự xuống dòng của nội dung trước khi băm |
| `-nosmimecap` | Bỏ phần khai năng lực S/MIME |
| `-signer` | Certificate được đính kèm trong cấu trúc CMS, để thiết bị biết chữ ký thuộc về ai |

### 2.3. Thứ tự file trong gói

SWUpdate đọc gói theo dạng luồng: khối cpio đầu tiên phải là `sw-description`, khối thứ hai là `sw-description.sig` rồi mới xử lý phần còn lại. Kiểm tra:

```bash
cpio -t < tmp-sensornode/deploy/images/bbb-sensornode/sensornode-image-swu-bbb-sensornode.swu
# sw-description
# sw-description.sig
# sw-description.in
# sensornode-image-bbb-sensornode.ext4.gz
```

`sw-description.in` là template gốc, bị đính kèm vì nằm trong `SRC_URI`. SWUpdate không dùng tới nó.

## 4. Recipe cấu hình device

Toàn bộ phần liên quan tới chữ ký trong `swupdate_%.bbappend`:

```bitbake
SRC_URI:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'file://signed-images.cfg', '', d)}"

SWUPDATE_PUBKEY_DST = "${sysconfdir}/swupdate/swupdate.pem"
SWUPDATE_PUBKEY_SRC = "${UBOOT_SIGN_KEYDIR}/${UBOOT_SIGN_KEYNAME}.crt"
SECURE_BOOT_ENABLED = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', '1', '0', d)}"

do_configure:prepend() {
    if [ "${SECURE_BOOT_ENABLED}" = "1" ]; then
        cat ${WORKDIR}/signed-images.cfg >> ${WORKDIR}/defconfig
    fi
}

do_install[depends] += "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'virtual/kernel:do_kernel_generate_rsa_keys', '', d)}"
do_install[file-checksums] += "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', '${SWUPDATE_PUBKEY_SRC}:%s' % os.path.exists(d.getVar('SWUPDATE_PUBKEY_SRC')), '', d)}"

do_install:append() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/swupdate.cfg.in ${D}${sysconfdir}/swupdate.cfg
    sed -i "s#@BOARD_NAME@#${OTA_BOARD_NAME}#g" ${D}${sysconfdir}/swupdate.cfg

    if [ "${SECURE_BOOT_ENABLED}" = "1" ]; then
        install -d ${D}${sysconfdir}/swupdate
        install -m 0644 ${SWUPDATE_PUBKEY_SRC} ${D}${SWUPDATE_PUBKEY_DST}
        sed -i "s#@PUBLIC_KEY_LINE@#    public-key-file = \"${SWUPDATE_PUBKEY_DST}\";#g" ${D}${sysconfdir}/swupdate.cfg
    else
        sed -i "/@PUBLIC_KEY_LINE@/d" ${D}${sysconfdir}/swupdate.cfg
    fi
    ...
}

FILES:${PN}:append = " \
    ${sysconfdir}/swupdate.cfg \
    ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', '${SWUPDATE_PUBKEY_DST}', '', d)} \
"
```

Bốn mục dưới đây bóc tách đoạn trên theo thứ tự thực thi.

### 4.1. Biến trung gian `SECURE_BOOT_ENABLED`

`bb.utils.contains` là biểu thức Python, không gọi được từ trong hàm shell. Cách xử lý là tính sẵn ra một biến `0`/`1` ở mức recipe rồi shell chỉ việc so chuỗi:

```bitbake
SECURE_BOOT_ENABLED = "${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', '1', '0', d)}"
```

Đây là pattern dùng lại được cho bất kỳ hàm task nào cần rẽ nhánh theo `DISTRO_FEATURES`. Viết trực tiếp `${@bb.utils.contains(...)}` trong thân hàm shell cũng chạy được nhưng khi biểu thức dài và lặp nhiều lần thì khó đọc và dễ sai dấu nháy.

### 4.2. Đưa option vào Kconfig của SWUpdate

Trong `swupdate_%.bbappend`:

```bitbake
SRC_URI:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', 'file://signed-images.cfg', '', d)}"

do_configure:prepend() {
    if [ "${SECURE_BOOT_ENABLED}" = "1" ]; then
        cat ${WORKDIR}/signed-images.cfg >> ${WORKDIR}/defconfig
    fi
}
```

| Chi tiết | Vì sao |
|---|---|
| `SRC_URI` có điều kiện | Chỉ tải file khi cần. Thêm vô điều kiện cũng không sai, nhưng khi tắt feature thì file nằm trong thư mục làm việc mà không ai dùng, dễ gây hiểu nhầm |
| Nối vào `defconfig` | SWUpdate cấu hình bằng Kconfig và chỉ đọc `defconfig`. File `.cfg` nằm trong `SRC_URI` không tự được đọc. Đây là điểm khác biệt với kernel và U-Boot, nơi class tự gom mọi file `.cfg` |
| Dùng `do_configure:prepend` | Phải nối xong trước khi task gốc chạy `oldconfig`. Nối sau thì defconfig đã được dùng rồi |
| Dùng `cat >>` | `signed-images.cfg` chỉ bổ sung vào cuối |

Nội dung `signed-images.cfg`:

```
CONFIG_SIGNED_IMAGES=y
CONFIG_SIGALG_CMS=y
# CONFIG_SIGALG_RAWRSA is not set
# CONFIG_SIGALG_RSAPSS is not set
# CONFIG_SIGALG_GPG is not set
CONFIG_CMS_IGNORE_CERTIFICATE_PURPOSE=y
CONFIG_CMS_IGNORE_EXPIRED_CERTIFICATE=y
```

| Option | Tác dụng |
|---|---|
| `CONFIG_SIGNED_IMAGES` | Bắt buộc mọi gói phải có chữ ký hợp lệ. Đồng thời bắt buộc mọi image có dữ liệu phải khai `sha256` |
| `CONFIG_SIGALG_CMS` | Chọn thuật toán CMS/X.509 |
| `CONFIG_CMS_IGNORE_EXPIRED_CERTIFICATE` | Certificate dev được generate tự động chỉ có hiệu lực 30 ngày, nếu hết hạn thì mọi gói bị từ chối -> cấu hình giúp ignore nó |
| `CONFIG_CMS_IGNORE_CERTIFICATE_PURPOSE` | Certificate cần khai báo mục đích ký code mà certificate dev được generate tự động không có điều này -> cấu hình giúp ignore nó |

Kiểm tra hạn của certificate đang dùng:

```bash
openssl x509 -in keys/dev.crt -noout -subject -startdate -enddate
# notBefore=Jun  7 11:28:24 2026 GMT
# notAfter=Jul  7 11:28:24 2026 GMT
```

Hệ quả: thiết bị vẫn kiểm tra chữ ký và chuỗi certificate, nhưng không còn khả năng vô hiệu hoá một khoá bằng cách để nó hết hạn. Với hệ thống thật nên sinh certificate có thời hạn dài, khai đúng mục đích ký code rồi tắt hai option này.

### 4.3. Certificate và file cấu hình

Template [swupdate.cfg.in](../../meta-sensornode/recipes-support/swupdate/files/swupdate.cfg.in) có một chỗ trống:

```
globals :
{
    verbose  = true;
    loglevel = 5;
    syslog   = true;
    reboot-required = false;
@PUBLIC_KEY_LINE@
};
```

`do_install:append` trong `swupdate_%.bbappend` xử lý chỗ trống như sau:

```
SWUPDATE_PUBKEY_DST = "${sysconfdir}/swupdate/swupdate.pem"
SWUPDATE_PUBKEY_SRC = "${UBOOT_SIGN_KEYDIR}/${UBOOT_SIGN_KEYNAME}.crt"

do_install:append() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/swupdate.cfg.in ${D}${sysconfdir}/swupdate.cfg
    sed -i "s#@BOARD_NAME@#${OTA_BOARD_NAME}#g" ${D}${sysconfdir}/swupdate.cfg

    if [ "${SECURE_BOOT_ENABLED}" = "1" ]; then
        install -d ${D}${sysconfdir}/swupdate
        install -m 0644 ${SWUPDATE_PUBKEY_SRC} ${D}${SWUPDATE_PUBKEY_DST}
        sed -i "s#@PUBLIC_KEY_LINE@#    public-key-file = \"${SWUPDATE_PUBKEY_DST}\";#g" ${D}${sysconfdir}/swupdate.cfg
    else
        sed -i "/@PUBLIC_KEY_LINE@/d" ${D}${sysconfdir}/swupdate.cfg
    fi

    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/09-swupdate-args ${D}${bindir}/09-swupdate-args
    sed -i \
        -e "s#@BOARD_NAME@#${OTA_BOARD_NAME}#g" \
        -e "s#@HW_REVISION@#${OTA_HW_REVISION}#g" \
        -e "s#@SLOT_A_DEV@#${SENSORNODE_SLOT_A_DEV}#g" \
        ${D}${bindir}/09-swupdate-args
}
```

Nếu bật feature `sensornode-secureboot` thì nó sẽ cài `dev.crt` vào `/etc/swupdate/swupdate.pem`. Sau đó, `sed` thay `@PUBLIC_KEY_LINE@` bằng dòng `public-key-file = "...";`. Nếu không thì nó sẽ xoá hẳn dòng placeholder.

Nhánh `else` là bắt buộc, không phải cho đẹp: `/etc/swupdate.cfg` được phân tích bằng libconfig để sót dòng `@PUBLIC_KEY_LINE@` thì file sai cú pháp và SWUpdate không chạy được. Quy tắc chung khi dùng template kiểu này: mỗi placeholder phải được xử lý ở mọi nhánh hoặc thay bằng giá trị hoặc xoá đi.

Cuối cùng, file certificate chỉ được liệt kê vào package khi feature bật:

```bitbake
FILES:${PN}:append = " ... ${@bb.utils.contains('DISTRO_FEATURES', 'sensornode-secureboot', '${SWUPDATE_PUBKEY_DST}', '', d)}"
```

Nếu liệt kê vô điều kiện, bản dev sẽ có một mục trong `FILES` trỏ tới file không tồn tại. Điều đó không làm hỏng build nhưng ngược lại cài file mà quên khai trong `FILES` sẽ khiến bước kiểm tra chất lượng báo lỗi `installed-vs-shipped`.

### 4.4. Hai varflag điều phối thứ tự và rebuild

```bitbake
do_install[depends] += "... virtual/kernel:do_kernel_generate_rsa_keys ..."
do_install[file-checksums] += "... ${SWUPDATE_PUBKEY_SRC}:<tồn tại hay chưa> ..."
```

| Varflag | Vấn đề nó giải quyết |
|---|---|
| `[depends]` | Cặp key không có sẵn trong repo mà do task `do_kernel_generate_rsa_keys` của kernel sinh ra khi `FIT_GENERATE_KEYS = "1"`. Không khai phụ thuộc này thì `do_install` của swupdate có thể chạy trước lúc key tồn tại và lỗi ngay ở lệnh `install` |
| `[file-checksums]` | Certificate nằm ngoài layer nên bitbake không tự theo dõi nội dung. Dòng này đưa nội dung certificate vào chữ ký của task: thay cặp key thì swupdate được build lại thay vì lấy bản cũ từ sstate |

Chi tiết cần biết về `file-checksums`: giá trị khai theo dạng `<đường dẫn>:<tồn tại hay chưa>`, trong đó phần thứ hai được tính lúc parse. Ở lần build đầu tiên trên một build directory sạch, key chưa tồn tại nên giá trị là `False`. Sau khi kernel sinh key, lần parse kế tiếp thấy `True` và task được chạy lại. Nghĩa là cơ chế này bảo vệ cho các lần build sau, không phải cho lần build đầu.

## 5. Quản lý khoá

| Khoá | Vai trò |
|---|---|---|
| `dev.key` | Ký FIT image và ký `sw-description` |
| `dev.crt` | Nhúng vào chữ ký, cài lên thiết bị làm root tin cậy |

Hệ quả thực tế của việc để khoá trong build directory:

- Xoá build directory, đổi máy build hoặc chạy CI sạch → `FIT_GENERATE_KEYS` sinh cặp khoá mới → thiết bị đang chạy từ chối mọi gói mới vì chữ ký không verify được với certificate cũ đã cài trong rootfs.
- Khôi phục bằng cách mang theo thư mục `keys/` sang máy build mới.

Nên đặt `UBOOT_SIGN_KEYDIR` trỏ tới thư mục ngoài repo, đặt `FIT_GENERATE_KEYS = "0"` để không bao giờ tự generate key và sao lưu private key ở nơi an toàn. Mất private key đồng nghĩa mất khả năng cập nhật toàn bộ thiết bị
