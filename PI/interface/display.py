import time
from smbus2 import SMBus
from PIL import Image

WIDTH  = 128
HEIGHT = 64
ADDR   = 0x3C
PAGES  = HEIGHT // 8

class SSD1309:
    def __init__(self, port=1):
        self.bus = SMBus(port)
        self.width = WIDTH
        self.height = HEIGHT
        self.size = (WIDTH, HEIGHT)
        self.mode = '1'
        self._init()

    def _cmd(self, *cmds):
        for c in cmds:
            self.bus.write_byte_data(ADDR, 0x00, c)

    def _data(self, buf):
        # send in 16-byte chunks (the most reliable way for I2C OLEDs)
        for i in range(0, len(buf), 16):
            self.bus.write_i2c_block_data(ADDR, 0x40, list(buf[i:i+16]))

    def _init(self):
        # 4-pin 2.42" I2C modules often use SH1106 logic or 
        # specific SSD1309 mappings. This is a robust Page-mode init.
        self._cmd(0xAE)           # display off
        self._cmd(0xD5, 0x80)     # clock div
        self._cmd(0xA8, 0x3F)     # mux ratio 64
        self._cmd(0xD3, 0x00)     # display offset 0
        self._cmd(0x40)           # start line 0
        self._cmd(0xA1)           # segment remap
        self._cmd(0xC8)           # COM scan direction
        self._cmd(0xDA, 0x12)     # COM pins HW config
        self._cmd(0x81, 0xCF)     # contrast
        self._cmd(0xD9, 0xF1)     # pre-charge
        self._cmd(0xDB, 0x40)     # VCOMH
        self._cmd(0x20, 0x02)     # Page Addressing Mode
        self._cmd(0xA4)           # output follows RAM
        self._cmd(0xA6)           # normal display
        self._cmd(0xAF)           # display ON
        time.sleep(0.1)
        self.clear()

    def clear(self):
        for page in range(PAGES):
            self._cmd(0xB0 | page)
            # Many 2.42" modules start columns at 0x02 (SH1106 offset)
            self._cmd(0x02) # Low column address
            self._cmd(0x10) # High column address
            self._data([0x00] * WIDTH)

    def display(self, image):
        img = image.convert('1').resize((WIDTH, HEIGHT))
        pixels = list(img.getdata())
        for page in range(PAGES):
            self._cmd(0xB0 | page)
            # Apply the 2-pixel column offset (Common for 2.42" modules)
            self._cmd(0x02) # Low col (Bit 0-3)
            self._cmd(0x10) # High col (Bit 4-7)
            
            buf = []
            for x in range(WIDTH):
                byte = 0
                for bit in range(8):
                    y = page * 8 + bit
                    if pixels[y * WIDTH + x]:
                        byte |= (1 << bit)
                buf.append(byte)
            self._data(buf)

    def contrast(self, level):
        self._cmd(0x81, level)

    def cleanup(self):
        self.clear()
        self._cmd(0xAE)
        self.bus.close()

def init_display():
    return SSD1309()
