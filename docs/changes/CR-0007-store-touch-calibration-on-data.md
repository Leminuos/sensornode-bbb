# CR-0007: store touch calibration on /data

Commit: `3874f28`

## Vấn đề

Unit `sensornode-ui.service`:

```ini
[Unit]
Description=SensorNode Qt HMI
After=multi-user.target data.mount

[Service]
...
Environment=TSLIB_CALIBFILE=/etc/pointercal
...
[Install]
WantedBy=multi-user.target
```

- tslib đọc và ghi file calib cảm ứng tại `/etc/pointercal`. Trên bản production, rootfs chỉ đọc nên không ghi được file calib vào đó.
- Unit vừa khai `WantedBy=multi-user.target` (là một phần của `multi-user.target`) vừa khai `After=multi-user.target` (phải chạy sau khi `multi-user.target` đã xong), tức vừa muốn chạy sau target lại vừa là thành phần của chính target đó. Hai khai báo mâu thuẫn nhau nên thứ tự khởi động không rõ ràng.

## Giải pháp

- Đặt `TSLIB_CALIBFILE=/data/config/pointercal`.
- Bỏ `After=multi-user.target`, chỉ giữ `After=data.mount network.target` và thêm `Wants=data.mount` để UI chạy sau khi `/data` đã mount.

Image production không có gói `ts_calibrate`. Muốn có file calib thì chạy `ts_calibrate` trên bản dev rồi copy file sang `/data/config/pointercal` của thiết bị production.
