# CR-0008: drop /data mountpoint from wks

Commit: `b26fb3c`

## Vấn đề

Rootfs của slot A trong file `.wic` (dùng để flash thẻ) khác với rootfs trong file `.ext4.gz` (dùng cho OTA) ở `/etc/fstab`, dù cả hai sinh ra từ cùng một lần build `sensornode-image`.

Tách rootA từ `.wic` và rootfs trong `.ext4.gz` rồi so sánh `/etc/fstab`:

```bash
dd if=sensornode-image-bbb-sensornode.wic of=rootA.ext4 bs=1M skip=4 count=160
zcat sensornode-image-bbb-sensornode.ext4.gz > ota.ext4
debugfs -R "cat /etc/fstab" rootA.ext4 | tail -1
debugfs -R "cat /etc/fstab" ota.ext4   | tail -1
```

```
/dev/mmcblk0p3	/data	ext4	defaults	0	0
#/dev/mmcblk0p1       /media/card          auto       defaults,sync,noauto  0  0
```

→ Slot A sau khi flash có thêm dòng mount `/data` theo đường dẫn thiết bị, option `defaults`. Slot cài qua OTA không có dòng này nên `/data` được mount bởi `data.mount`. Chức năng vẫn chạy, nhưng hai slot không giống nhau.

## Nguyên nhân

Dòng `/data` trong hai file wks khai mountpoint:

```
part /data --source rawcopy --ondisk mmcblk0 --fstype=ext4 --align 4096 --fixed-size ${SENSORNODE_DATA_SIZE_MiB} --sourceparams="file=${SENSORNODE_DATA_IMG}"
```

wic dùng mountpoint này để sửa `/etc/fstab` của partition `/` khi ghi `.wic` trong `poky/scripts/lib/wic/plugins/imager/direct.py`:

```python
for part in self.parts:
    if not part.realnum or not part.mountpoint \
       or part.mountpoint == "/" or not (part.mountpoint.startswith('/') or part.mountpoint == "swap"):
        continue
    ...
    else:
        # mmc device partitions are named mmcblk0p1, mmcblk0p2..
        prefix = 'p' if  part.disk.startswith('mmcblk') else ''
        device_name = "/dev/%s%s%d" % (part.disk, prefix, part.realnum)

    opts = part.fsopts if part.fsopts else "defaults"
    line = "\t".join([device_name, part.mountpoint, part.fstype,
                      opts, "0", "0"]) + "\n"
    fstab_lines.append(line)
```

→ Mọi `part` có mountpoint khác `/` đều được nối thêm một dòng vào fstab. Partition `/data` không dùng `--use-uuid`/`--use-label` nên wic ghi theo tên thiết bị `/dev/mmcblk0p3`, option `defaults`. Việc sửa này chỉ xảy ra với rootfs nằm trong `.wic` còn `.ext4.gz` là bản rootfs gốc từ `do_image_ext4` nên không có dòng này.

## Giải pháp

Bỏ mountpoint `/data` khỏi dòng `part` trong `bbb-sensornode-ab.wks.in` và `bbb-sensornode-single.wks.in`, chỉ giữ `part --source rawcopy ...`. wic vẫn ghi `sensornode-data.ext4` vào partition thứ 3 như cũ nhưng không sửa fstab nữa. Việc mount `/data` chỉ còn một nguồn duy nhất là `data.mount`, giống nhau trên cả slot flash lẫn slot OTA.
