#
# SensorNode peripherals attached to the BBB:
#   - ILI9341 240x320 TFT on SPI1 (tinydrm) + resistive touch
#   - SHT30 and BH1750 on I2C1
#   - PWM backlight
#

MACHINE_EXTRA_RRECOMMENDS += " \
    kernel-module-ili9341 \
    kernel-module-drm-mipi-dbi \
"
