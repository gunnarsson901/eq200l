import smbus2, time

bus = smbus2.SMBus(1)
addr = 0x3C

def cmd(*args):
    for c in args:
        bus.write_byte_data(addr, 0x00, c)

# Proper SSD1309 init (no charge pump, external VCC)
cmd(0xAE)           # display off
cmd(0xD5, 0x80)     # clock div
cmd(0xA8, 0x3F)     # mux ratio 64
cmd(0xD3, 0x00)     # display offset 0
cmd(0x40)           # start line 0
cmd(0xA1)           # segment remap (mirror horizontally)
cmd(0xC8)           # COM scan direction (mirror vertically)
cmd(0xDA, 0x12)     # COM pins
cmd(0x81, 0xFF)     # max contrast
cmd(0xD9, 0x25)     # pre-charge (external VCC)
cmd(0xDB, 0x34)     # VCOMH
cmd(0x20, 0x00)     # horizontal addressing mode
cmd(0xA4)           # output follows RAM
cmd(0xA6)           # normal display (not inverted)
cmd(0xAF)           # display ON
time.sleep(0.1)

# Fill all 8 pages with 0xFF (every pixel on)
cmd(0x21, 0x00, 0x7F)   # column 0-127
cmd(0x22, 0x00, 0x07)   # page 0-7
for _ in range(128 * 8 // 16):
    bus.write_i2c_block_data(addr, 0x40, [0xFF] * 16)

print('Screen should be fully lit white')
time.sleep(3)

# Now try inverse: all pixels OFF to confirm display is responding
cmd(0xA7)   # invert display
print('Now inverted — should be fully black')
time.sleep(3)

cmd(0xA6)   # back to normal
print('done')
