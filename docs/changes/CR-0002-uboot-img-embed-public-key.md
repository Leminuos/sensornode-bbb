# CR-0002: u-boot.img does not embed the public key

Commit: `f01f36d`

## Vấn đề

Theo thiết kế, U-Boot của bản production phải từ chối boot mọi `fitImage` không mang chữ ký hợp lệ. Tuy nhiên, khi test với artifact chứa `fitImage` không hợp lệ và log hiện:

```
`Verifying Hash Integrity ... OK`
```

Kernel boot bình thường và hệ thống lên tới `bbb-sensornode login:`

Nếu verified boot hoạt động đúng, thì phải dừng ở bước kiểm tra cấu hình:

```
## Loading kernel from FIT Image at 82000000 ...
   Using 'conf-am335x-boneblack.dtb' configuration
   Verifying Hash Integrity ... Failed to verify required signature 'key-dev'
Bad Data Hash
```

> [!TIP]
> Tạo `fitImage` không hợp lệ từ artifact có sẵn:
>
>
> ```bash
> D=tmp-sensornode/deploy/images/bbb-sensornode
> cp $D/fitImage /tmp/fitImage-unsigned
> fdtput -r /tmp/fitImage-unsigned /configurations/conf-am335x-boneblack.dtb/signature-1
> ```
> 
> Xác nhận chữ ký đã mất:
> 
> ```bash
> dumpimage -l /tmp/fitImage-unsigned | grep -c 'Sign algo'   # 0
> dumpimage -l $D/fitImage | grep 'Sign algo'      			# Sign algo: sha256,rsa2048:dev
> ```
> 
> Sau đó, ghi đè `fitImage` trên thẻ SD:
> 
> ```bash
> sudo mount /dev/sdX1 /mnt
> sudo cp /mnt/boot/fitImage /mnt/boot/fitImage.bak
> sudo cp /tmp/fitImage-unsigned /mnt/boot/fitImage
> sudo sync && sudo umount /mnt
> ```

## Root Cause

Check tại prompt U-Boot:

```
=> fdt addr ${fdtcontroladdr}
=> fdt list /signature
```

Output:

```
libfdt fdt_path_offset() returned FDT_ERR_NOTFOUND
```

→ Public key không có trong control DTB của U-Boot.

Control DTB là devicetree mà U-Boot dùng để mô tả chính nó lúc chạy. Public key phải nằm trong node `/signature/key-dev` của DTB đó.

Tuy nhiên, khi check DTB `u-boot.dtb` trên máy build thì vẫn có public key:

```bash
$ fdtget -l $D/u-boot.dtb /signature
key-dev
```

→ DTB `u-boot.dtb` chưa được apply vào `u-boot.img`.

## Phân tích chi tiết

Khi check artifact `u-boot.img` trên máy build:

```bash
D=tmp-sensornode/deploy/images/bbb-sensornode
dumpimage -l $D/u-boot.img
```

Output:

```
pei@nguyen-bui:~/workspace/yocto/build-sensornode$ dumpimage -l $D/u-boot.img
FIT description: Firmware image with one or more FDT blobs
Created:         Tue Jan 11 01:46:34 2022
 Image 0 (firmware-1)
  Description:  U-Boot 2022.01 for am335x board
  Created:      Tue Jan 11 01:46:34 2022
  Type:         Firmware
  Compression:  uncompressed
  Data Size:    560652 Bytes = 547.51 KiB = 0.53 MiB
  Architecture: ARM
  OS:           U-Boot
  Load Address: 0x80800000
  Hash algo:    crc32
  Hash value:   5d3aab3f
 ...
 ...
 Image 4 (fdt-4)
  Description:  am335x-boneblack
  Created:      Tue Jan 11 01:46:34 2022
  Type:         Flat Device Tree
  Compression:  uncompressed
  Data Size:    85336 Bytes = 83.34 KiB = 0.08 MiB
  Architecture: ARM
  Hash algo:    crc32
  Hash value:   26ac5bf1
 ...
 ...
 Image 8 (fdt-8)
  Description:  am335x-pocketbeagle
  Created:      Tue Jan 11 01:46:34 2022
  Type:         Flat Device Tree
  Compression:  uncompressed
  Data Size:    79248 Bytes = 77.39 KiB = 0.08 MiB
  Architecture: ARM
  Hash algo:    crc32
  Hash value:   2289be78
 Default Configuration: 'conf-1'
 Configuration 0 (conf-1)
  Description:  am335x-evm
  Kernel:       unavailable
  Firmware:     firmware-1
  FDT:          fdt-1
  Loadables:    firmware-1
 ...
 ...
 Configuration 3 (conf-4)
  Description:  am335x-boneblack
  Kernel:       unavailable
  Firmware:     firmware-1
  FDT:          fdt-4
  Loadables:    firmware-1
 ...
 ...
 Configuration 7 (conf-8)
  Description:  am335x-pocketbeagle
  Kernel:       unavailable
  Firmware:     firmware-1
  FDT:          fdt-8
  Loadables:    firmware-1
```

Kết quả cho thấy artifact `u-boot.img` không phải binary U-Boot thuần mà là binary dạng FIT và chứa rất nhiều blob control DTB.

Điều này là do cấu hình `CONFIG_SPL_LOAD_FIT` được enable trong `am335x_evm_defconfig` của upstream U-Boot.

Với option này, rule tạo `u-boot.img` như sau:

```make
ifdef CONFIG_SPL_LOAD_FIT
MKIMAGEFLAGS_u-boot.img = -f auto -A $(ARCH) -T firmware -C none -O u-boot ... -E \
	$(patsubst %,-b arch/$(ARCH)/dts/%.dtb,$(subst ",,$(CONFIG_OF_LIST)))
```

Tức là, các DTB trong FIT được lấy từ `arch/arm/dts/*.dtb` theo `CONFIG_OF_LIST`, không phải `u-boot.dtb` trong `DEPLOYDIR`.

>[!NOTE] Vì sao core code TI lại bật FIT cho U-boot?
> Một SPL cần phải phục vụ 8 board khác nhau. `board/ti/am335x/board.c` trong U-Boot 2022.01:
>
>```
> int board_fit_config_name_match(const char *name)
> {
> 	if (board_is_gp_evm()  && !strcmp(name, "am335x-evm"))        return 0;
> 	else if (board_is_bone()    && !strcmp(name, "am335x-bone"))       return 0;
> 	else if (board_is_bone_lt() && !strcmp(name, "am335x-boneblack"))  return 0;
> 	else if (board_is_pb()      && !strcmp(name, "am335x-pocketbeagle")) return 0;
> 	... /* evmsk, bonegreen, icev2, sancloud-bbe */
> }
> ```
>
> SPL đọc EEPROM trên board để biết đang chạy trên BeagleBone Black rồi chọn config `am335x-boneblack` trong FIT và truyền đúng DTB đó sang U-Boot. Legacy uImage chỉ chở được một payload nên không làm được việc này.

Đó là nguyên nhân vì sao mà `u-boot.dtb` không có DTB chứa key. Tuy nhiên, khi boot thì tại sao U-Boot không báo lỗi?

Trong `boot/image-fit-sig.c`, hàm `fit_config_verify_required_sigs()`:

```c
	sig_node = fdt_subnode_offset(sig_blob, 0, FIT_SIG_NODENAME);
	if (sig_node < 0) {
		debug("%s: No signature node found: %s\n", ...);
		return 0;	/* không có key required = danh sách rỗng = PASS */
	}
```

Không có key nào khai báo `required = "conf"` thì danh sách signature rỗng và rỗng được coi là thỏa mãn. U-Boot vẫn kiểm tra hash sha256 của FIT nên phát hiện được image hỏng, nhưng nó nhận mọi `fitImage` dù không sign.

## Giải pháp

Tắt `CONFIG_SPL_LOAD_FIT` để sử dụng legecy U-Boot:

```diff
 CONFIG_CMD_BOOTM=y
 CONFIG_BOOTM_LINUX=y
+
+# CONFIG_SPL_LOAD_FIT is not set
+CONFIG_SPL_LEGACY_IMAGE_SUPPORT=y
+CONFIG_SPL_LEGACY_IMAGE_CRC_CHECK=y
```

Lúc này, rule tạo `u-boot.img` sẽ như sau:

```
u-boot-dtb.img u-boot.img ...: \
    $(if $(CONFIG_SPL_LOAD_FIT), u-boot-nodtb.bin $(if ...,dts/dt.dtb) , $(UBOOT_BIN)) FORCE
```

Chuỗi trở thành:

```
u-boot.dtb (đã có key)
   │  EXT_DTB
   ▼
dts/dt.dtb ──────┐
                 ├── cat ──► u-boot-dtb.bin ──► u-boot.bin
u-boot-nodtb.bin ┘                                 │
                                                   ▼
                                             mkimage -T firmware
                                                   │
                                                   ▼
                                                u-boot.img
```

Chuỗi này là hoạt động của của class [uboot-sign](#poky/meta/classes/uboot-sign.bbclass), không cần thêm task hay bbappend nào.

Cấu hình `CONFIG_SPL_LEGACY_IMAGE_SUPPORT` cần được bật. Nếu thiếu thì `spl_legacy.o` không được biên dịch và gây ra lỗi sau:

```
U-Boot SPL 2022.01 (Jan 10 2022 - 18:46:34 +0000)
Trying to boot from MMC1
mmc_load_image_raw_sector: mmc block read error
spl_register_fat_device: fat register err - -1
spl_load_image_fat: error reading image u-boot.img, err - -1
SPL: failed to boot from all boot devices
### ERROR ### Please RESET the board ###
```

Cấu hình `CONFIG_SPL_LEGACY_IMAGE_CRC_CHECK` kiểm tra toàn vẹn khi SPL nạp U-Boot, thay cho hash crc32 từng sub-image mà FIT có sẵn trước đó.

## Kiểm chứng

Trên máy build:

```bash
D=tmp-sensornode/deploy/images/bbb-sensornode
dumpimage -l $D/u-boot.img   # Legacy U-Boot
```

Trên board, tại prompt U-Boot:

```
=> fdt addr ${fdtcontroladdr}
=> fdt list /signature
```

Phải in ra node `key-dev`.
