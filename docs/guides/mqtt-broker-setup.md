# Chạy MQTT broker trên máy host

Guide này cài Mosquitto trên máy host để board gửi số liệu cảm biến và nhận thông báo OTA. Host có thể là Windows hoặc Ubuntu/Debian, chỉ cần nằm cùng LAN với board.

```
   Router (DHCP)
   ├── BBB (IP động)  sensornode-telemetryd, sensornode-otad
   └── Host           mosquitto :1883, ota_server.py :8000
```

Board nhận IP qua DHCP và gọi broker bằng `SENSORNODE_MQTT_HOST` (mặc định đặt trong `meta-sensornode/conf/include/sensornode-vars.inc`). Nên đặt giá trị này là tên mDNS của host (`<hostname>.local`) để đổi router không phải build lại.

## 1. Cài mosquitto

Ubuntu/Debian:

```bash
sudo apt install -y mosquitto mosquitto-clients
```

Windows: cài bằng bộ cài trên mosquitto.org, broker chạy thành service `mosquitto`. Thêm thư mục cài vào `PATH` để dùng được `mosquitto_sub`/`mosquitto_pub`.

## 2. Cấu hình broker listen ra LAN

Mosquitto 2.x mặc định chỉ listen `localhost`. Thêm vào file cấu hình (Ubuntu: `/etc/mosquitto/conf.d/sensornode.conf`, Windows: `mosquitto.conf` trong thư mục cài):

```conf
listener 1883 0.0.0.0
protocol mqtt

# Lab: không auth
allow_anonymous true
```

> `allow_anonymous true` chỉ dùng trong lab, production phải bật auth.

Restart broker:

```bash
sudo systemctl restart mosquitto        # Ubuntu
```

```powershell
Restart-Service mosquitto               # Windows, PowerShell admin
```

Nếu Windows báo `Only one usage of each socket address`, port 1883 đang bị process khác giữ. Tìm bằng `netstat -ano | findstr :1883` rồi `Get-Process -Id <PID>`.

## 3. Mở firewall

Ubuntu (nếu bật ufw):

```bash
sudo ufw allow 1883/tcp
sudo ufw allow 8000/tcp
```

Windows: đặt mạng đang dùng là **Private**, rồi trong PowerShell admin:

```powershell
New-NetFirewallRule -DisplayName "SensorNode MQTT" -Direction Inbound -Protocol TCP -LocalPort 1883 -Profile Private -Action Allow
New-NetFirewallRule -DisplayName "SensorNode OTA"  -Direction Inbound -Protocol TCP -LocalPort 8000 -Profile Private -Action Allow
```

## 4. Chạy OTA server

```bash
python3 tools/ota-server/ota_server.py
```

URL trong manifest mặc định dùng `<hostname>.local` của máy chạy script. Đặt `OTA_HOST` để dùng tên hoặc IP khác, `OTA_RELEASE_DIR` để đổi thư mục chứa `.swu`. PowerShell: `$env:OTA_HOST="192.168.1.20"; python ota_server.py`.

## 5. Kiểm tra

Trên host:

```bash
netstat -ano | findstr :1883          # Windows, phải thấy 0.0.0.0:1883
ss -tlnp | grep 1883                  # Ubuntu
mosquitto_sub -h localhost -t 'sensornode/#' -v
```

Trên board:

```bash
networkctl status eth0                # IP do router cấp
resolvectl query <hostname>.local     # mDNS phân giải ra IP host
journalctl -u sensornode-telemetryd -f
```

## 6. Đổi địa chỉ broker

Đặt trong `build-sensornode/conf/local.conf` rồi build lại:

```
SENSORNODE_MQTT_HOST = "<hostname>.local"
```

Sửa tạm trên board không cần build: sửa `--mqtt-host` trong `/etc/default/sensornode-telemetryd` và `/etc/default/sensornode-otad`, rồi `systemctl restart sensornode-telemetryd sensornode-otad`. Với distro có `sensornode-readonly`, file sửa nằm ở lớp upper trên `/data` và che bản trong image mới sau OTA, xoá nó trong `/data/overlay-etc/upper/default/` khi không dùng nữa.
