import RPi.GPIO as GPIO
import time
from display import init_display
from PIL import Image, ImageDraw

PINS = {'UP': 20, 'DOWN': 21, 'LEFT': 13, 'RIGHT': 26, 'SELECT': 16}

GPIO.setmode(GPIO.BCM)
for pin in PINS.values():
    GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)

device = init_display()

def show(text):
    img = Image.new('1', (128, 64), 0)
    d = ImageDraw.Draw(img)
    d.text((4, 4),  'Button test:', fill=255)
    d.text((4, 20), text, fill=255)
    d.text((4, 48), 'Press any button', fill=255)
    device.display(img)

show('waiting...')
last = {pin: 1 for pin in PINS.values()}

print('Watch the display and press buttons for 15s...')
for _ in range(750):
    for name, pin in PINS.items():
        state = GPIO.input(pin)
        if state == 0 and last[pin] == 1:
            print(f'PRESSED: {name}')
            show(f'PRESSED: {name}')
        last[pin] = state
    time.sleep(0.02)

device.cleanup()
GPIO.cleanup()
print('done')
