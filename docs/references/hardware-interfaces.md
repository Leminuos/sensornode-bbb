# Hardware interfaces

Bảng tra cách từng linh kiện nối vào BeagleBone Black: bus, địa chỉ, chân header, driver kernel và node trong userspace.

## Linh kiện

| Linh kiện | Bus | Địa chỉ / CS | Driver kernel | Userspace |
|---|---|---|---|---|
| SHT30 | I2C1 | `0x44` | `i2c-dev` | `/dev/i2c-1` |
| BH1750 | I2C1 | `0x23` | `i2c-dev` | `/dev/i2c-1` |
| ILI9341 240×320 | SPI1 | CS0, 24 MHz | `ili9341` (tinydrm) | `/dev/fb0` (Qt `linuxfb`) |
| XPT2046 touch | SPI0 | CS0, 1 MHz | `ads7846` | `/dev/input/event0` (tslib) |
| Backlight | eHRPWM1 | Channel 0 | `pwm-tiehrpwm` | `/sys/class/pwm/pwmchip0/pwm0` |
| Console | UART0 | — | built-in | `ttyO0`, 115200 8N1 |
| Mạng | Ethernet | — | built-in | `eth0`, static IP `192.168.137.100/24` |

## Cách nối

| Tín hiệu | Chân |
|---|---|
| I2C1 SDA | P9_26 |
| I2C1 SCL | P9_24 |
| SPI1 SCLK (LCD) | P9_31 |
| SPI1 MISO (LCD) | P9_29 |
| SPI1 MOSI (LCD) | P9_30 |
| SPI1 CS0 (LCD) | P9_28 |
| LCD DC | P9_27 |
| LCD RESET | P9_25 |
| SPI0 SCLK (touch) | P9_22 |
| SPI0 MISO (touch) | P9_21 |
| SPI0 MOSI (touch) | P9_18 |
| SPI0 CS0 (touch) | P9_17 |
| Touch IRQ (T_INT) | P9_12 |
| Backlight PWM | P9_14 |
| UART0 debug | J1: GND pin 1, RX pin 4, TX pin 5 |
