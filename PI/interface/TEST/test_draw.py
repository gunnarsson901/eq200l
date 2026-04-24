from display import SSD1309
from PIL import Image, ImageDraw
import time

d = SSD1309()

# Test 1: solid white rectangle top half
print('Test 1: top half white')
img = Image.new('1', (128, 64), 0)
draw = ImageDraw.Draw(img)
draw.rectangle([0, 0, 127, 31], fill=255)
pixels = list(img.getdata())
print(f'  white pixels: {sum(1 for p in pixels if p > 0)}')
d.display(img)
time.sleep(3)

# Test 2: white rectangle bottom half
print('Test 2: bottom half white')
img = Image.new('1', (128, 64), 0)
draw = ImageDraw.Draw(img)
draw.rectangle([0, 32, 127, 63], fill=255)
d.display(img)
time.sleep(3)

# Test 3: vertical stripe left half
print('Test 3: left half white')
img = Image.new('1', (128, 64), 0)
draw = ImageDraw.Draw(img)
draw.rectangle([0, 0, 63, 63], fill=255)
d.display(img)
time.sleep(3)

# Test 4: raw bytes — write 0xFF directly per page, skip image entirely
print('Test 4: raw 0xFF direct page write')
for page in range(8):
    d._cmd(0xB0 | page)
    d._cmd(0x00)
    d._cmd(0x10)
    d._data([0xFF] * 128)
time.sleep(3)

d.cleanup()
print('done')
