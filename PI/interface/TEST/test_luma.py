import time
from luma.core.interface.serial import i2c
from luma.oled.device import ssd1309
from luma.core.render import canvas
from PIL import Image, ImageDraw

serial = i2c(port=1, address=0x3C)
device = ssd1309(serial, width=128, height=64)
device.contrast(255)

print('Test 1: solid white fill')
with canvas(device) as draw:
    draw.rectangle([0, 0, 127, 63], fill='white')
time.sleep(3)

print('Test 2: solid black fill')
with canvas(device) as draw:
    draw.rectangle([0, 0, 127, 63], fill='black')
time.sleep(3)

print('Test 3: white text on black')
with canvas(device) as draw:
    draw.text((0, 0),  'Line 1 top', fill='white')
    draw.text((0, 20), 'Line 2 mid', fill='white')
    draw.text((0, 40), 'Line 3 bot', fill='white')
time.sleep(3)

print('Test 4: try rotate=2')
device2 = ssd1309(serial, width=128, height=64, rotate=2)
device2.contrast(255)
with canvas(device2) as draw:
    draw.rectangle([0, 0, 127, 63], fill='white')
time.sleep(3)

print('done')
