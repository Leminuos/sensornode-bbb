# Chạy NTP server trên máy host

Board đồng bộ giờ bằng `systemd-timesyncd`, thử lần lượt các server trong `SENSORNODE_NTP_SERVERS`. Mặc định là `192.168.137.10` trước, sau đó mới tới `pool.ntp.org`. Nhờ vậy trong LAN không có Internet, board vẫn lấy được giờ từ host. Guide này dựng NTP server bằng chrony trên host Ubuntu/Debian.

```
   BBB (192.168.137.100)                Host (192.168.137.10)
   +----------------------+   UDP 123   +----------------------+
   | systemd-timesyncd    | ----------> | chrony               |
   +----------------------+             +----------------------+
```

## 1. Cài chrony

```bash
sudo apt update
sudo apt install -y chrony
```

Cài chrony sẽ gỡ `systemd-timesyncd` của host, vì hai dịch vụ không chạy song song được.

## 2. Cho subnet của board hỏi giờ

Tạo file `/etc/chrony/conf.d/sensornode.conf`:

```conf
allow 192.168.137.0/24
local stratum 10
```

- `allow` mở NTP cho subnet của board. Mặc định chrony chỉ là client, không trả lời máy khác.
- `local stratum 10` cho chrony vẫn trả giờ của chính host khi host mất Internet. Thiếu dòng này thì chrony không trả lời cho tới khi nó tự đồng bộ được với upstream.

Restart chrony:

```bash
sudo systemctl restart chrony
sudo systemctl enable chrony
```

## 3. Mở firewall (nếu host bật ufw)

```bash
sudo ufw allow from 192.168.137.0/24 to any port 123 proto udp
```

## 4. Kiểm tra

Trên host, xem chrony đã listen và board đã hỏi giờ chưa:

```bash
ss -ulnp | grep ':123'
sudo chronyc clients
```

Sau khi board boot, `chronyc clients` phải có dòng `192.168.137.100` với cột `NTP` lớn hơn 0.

Trên board bản dev:

```bash
timedatectl timesync-status
```

## 5. Đổi địa chỉ NTP server

Host đổi IP thì đặt lại biến trong `build-sensornode/conf/local.conf` rồi build lại image:

```conf
SENSORNODE_NTP_SERVERS = "192.168.1.20 0.pool.ntp.org"
```
