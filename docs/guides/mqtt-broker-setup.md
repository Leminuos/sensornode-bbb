# Chạy MQTT broker trên máy host

Guide này hướng dẫn cách cài Mosquitto trên máy host (Ubuntu/Debian) để board gửi số liệu cảm biến và nhận thông báo OTA.

```
   BBB (192.168.137.100)                 Host / gateway (192.168.137.1)
   +---------------------+               +-----------------------+
   | sensornode-ui       |   TCP 1883    | mosquitto broker      |
   |  (MQTT client)      | ------------> |  listener 1883 (mqtt) |
   +---------------------+               +-----------------------+
```

## 1. Cài mosquitto trên host (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install -y mosquitto mosquitto-clients
```

## 2. Cấu hình broker listen ra LAN

Mosquitto 2.x mặc định chỉ listen `localhost`. Phải khai báo listener bind ra interface LAN để BBB kết nối được. Tạo file `/etc/mosquitto/conf.d/sensornode.conf`:

```conf
# MQTT cho BBB client
listener 1883 0.0.0.0
protocol mqtt

# WebSockets cho dashboard web (nếu cần)
listener 9001 0.0.0.0
protocol websockets

# Lab/internal: không auth
allow_anonymous true
```

>`allow_anonymous true` chỉ chấp nhận được trong môi trường lab/internal — production phải bật auth.

Restart broker:

```bash
sudo systemctl restart mosquitto
sudo systemctl enable mosquitto      # chạy lại sau reboot host
```

## 3. Mở firewall (nếu host bật ufw)

```bash
sudo ufw allow from 192.168.137.0/24 to any port 1883 proto tcp
sudo ufw allow from 192.168.137.0/24 to any port 9001 proto tcp
```

Cách kiểm tra host có bật ufw không:

```bash
sudo ufw status
```

## 4. Kiểm tra kết quả

Trên máy host:

```bash
ss -tlnp | grep -E '1883|9001'      # phải thấy 0.0.0.0:1883
mosquitto_sub -h 192.168.137.1 -t 'sensor/#' -v
```

Trên board:

```bash
journalctl -u sensornode-ui -f        # thấy log kết nối broker thành công
mosquitto_pub -h 192.168.137.1 -t 'test/bbb' -m 'hello from bbb'
```

## 5. Đổi địa chỉ broker

Nếu IP host khác `192.168.137.10`, sửa trên board - không cần build lại:

```bash
vi /data/config/mqtt.json          # {"host": "<ip-host>", "port": 1883}
systemctl restart sensornode-ui
```

File nằm trên `/data` nên giữ nguyên qua reboot và OTA.
