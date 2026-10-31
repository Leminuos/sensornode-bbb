#
# SensorNode peripherals attached to the BBB:
#   - ILI9341 240x320 TFT on SPI1 (tinydrm) + resistive touch
#   - SHT30, BH1750 and DS3231 RTC on I2C1
#   - PWM backlight
#   - RTL8188EU WiFi dongle
#

MACHINE_EXTRA_RRECOMMENDS += " \
    kernel-module-ili9341 \
    kernel-module-drm-mipi-dbi \
    rtl8188eu \
"
