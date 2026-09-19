# MQTT topics

Bảng tra các topic và payload MQTT mà SensorNode dùng ở trạng thái hiện tại.

## Topic

| Topic | Direction | QoS | Retained | Chu kỳ |
|---|---|---|---|---|
| `sensor/temp` | board → host | 0 | có | 60 s |
| `sensor/humi` | board → host | 0 | có | 60 s |
| `sensor/lux` | board → host | 0 | có | 60 s |
| `ota/latest` | host → board | subscribe QoS 1 | có | khi phát hiện `.swu` mới |

Board chỉ publish khi đang kết nối broker; mất kết nối thì bỏ qua lần đọc đó.

Tên topic `ota/latest` đổi được qua key `mqtt-topic` trong `ota.json`; các topic `sensor/*` là hằng trong code.

## Payload `sensor/*`

Chuỗi số dạng text, không có đơn vị, không có timestamp.

| Topic | Kiểu | Đơn vị | Ví dụ |
|---|---|---|---|
| `sensor/temp` | float | °C | `27.4` |
| `sensor/humi` | int | %RH | `63` |
| `sensor/lux` | int | lux | `312` |

## Payload `ota/latest`

JSON, cùng nội dung với `GET /manifest.json` của OTA server.

| Key | Kiểu | Ý nghĩa |
|---|---|---|
| `version` | string | Version firmware, so với `/etc/sw-versions` |
| `url` | string | URL HTTP tới file `.swu`, đưa thẳng cho SWUpdate downloader |
| `size` | int | Kích thước file `.swu` (byte) |
| `sha256` | string | SHA256 của file `.swu` (hex, chữ thường) |

```json
{
  "version": "0.1.3",
  "url": "http://192.168.137.10:8000/release/sensornode-image-swu-bbb-sensornode-0.1.3.swu",
  "size": 47127040,
  "sha256": "075bcfc25672d026e67304d6d41019d8fc468192a9f713c1924aba1913d2d577"
}
```

## Broker

| Listener | Port | Protocol | Auth |
|---|---|---|---|
| MQTT | 1883 | `mqtt` | `allow_anonymous true` (chỉ lab) |
| WebSockets | 9001 | `websockets` | `allow_anonymous true` (chỉ lab) |

Cấu hình broker: [mqtt-broker-setup.md](../guides/mqtt-broker-setup.md).
