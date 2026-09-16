# Runtime config

Bảng tra các file cấu hình `sensornode-ui` trên `/data/config/` và biến môi trường liên quan.

## File `mqtt.json`

| Key | Kiểu | Mặc định | Ý nghĩa |
|---|---|---|---|
| `host` | string | `192.168.137.10` | Địa chỉ broker |
| `port` | int | `1883` | Port broker |

## File `ota.json`

| Key | Kiểu | Mặc định | Ý nghĩa |
|---|---|---|---|
| `auto-mode` | bool | `false` | Tự bật popup khi có bản mới |
| `manifest-url` | string | `http://192.168.137.10:8000/manifest.json` | URL manifest |
| `mqtt-topic` | string | `ota/latest` | Topic chứa manifest |
| `force-update` | bool | `false` | Bỏ qua so sánh version |
| `polling-interval-sec` | int | `60` | Chu kỳ poll manifest, `0` = tắt |

File `ota.json` được tạo sẵn trong image đang để `force-update: true`, cần tắt trước khi dùng thật.

## File `setting.json`

| Key | Kiểu | Mặc định | Ý nghĩa |
|---|---|---|---|
| `brightness` | int `0..100` | `72` | Độ sáng màn hình |

Thiếu file hoặc JSON hỏng thì app dùng giá trị mặc định. File trên `/data` giữ nguyên qua reboot và OTA.

## Biến môi trường

| Biến | Mặc định |
|---|---|
| `MQTT_CONFIG_FILE` | `/data/config/mqtt.json` |
| `OTA_CONFIG_FILE` | `/data/config/ota.json` |
| `APP_CONFIG_FILE` | `/data/config/setting.json` |
| `SENSOR_LOG_FILE` | `/data/logs/sensors.csv` |
| `OTA_SWUPDATE_TOOL` | `/usr/bin/09-swupdate-args` |
| `OTA_SWUPDATE_PROGRESS` | `/tmp/swupdateprog` |
| `OTA_VERSION_FILE` | `/etc/sw-versions` |
| `TSLIB_TSDEVICE` | `/dev/input/event0` |
| `TSLIB_CONFFILE` | `/etc/ts.conf` |
| `TSLIB_CALIBFILE` | `/etc/pointercal` |
| `TSLIB_FBDEVICE` | `/dev/fb0` |

Các biến `TSLIB_*` được set trong `sensornode-ui.service`.
