import time
from PIL import Image, ImageDraw
from display import init_display
from buttons import init_buttons, poll, cleanup

MENU = [
    'Option 1',
    'Option 2',
    'Option 3',
    'Option 4',
    'Option 5',
    'Option 6',
    'Option 7',
]

ROW_H   = 12   # pixels per row
VISIBLE = 5    # rows visible at once (5 * 12 = 60px)


def render(device, items, cursor, scroll):
    img = Image.new('1', (device.width, device.height), 0)
    d   = ImageDraw.Draw(img)

    for i, item in enumerate(items[scroll:scroll + VISIBLE]):
        y   = i * ROW_H + 2
        idx = scroll + i
        if idx == cursor:
            d.rectangle([0, y - 1, device.width - 4, y + ROW_H - 2], fill=255)
            d.text((6, y), item, fill=0)
        else:
            d.text((6, y), item, fill=255)

    # scroll bar on right edge
    if len(items) > VISIBLE:
        bar_h = max(4, device.height * VISIBLE // len(items))
        bar_y = (device.height - bar_h) * scroll // (len(items) - VISIBLE)
        d.rectangle([device.width - 3, bar_y, device.width - 1, bar_y + bar_h - 1], fill=255)

    device.display(img)


def main():
    device = init_display()
    cursor = 0
    scroll = 0
    dirty  = True

    def on_button(name):
        nonlocal cursor, scroll, dirty
        if name == 'up':
            if cursor > 0:
                cursor -= 1
                if cursor < scroll:
                    scroll = cursor
                dirty = True
        elif name == 'down':
            if cursor < len(MENU) - 1:
                cursor += 1
                if cursor >= scroll + VISIBLE:
                    scroll = cursor - VISIBLE + 1
                dirty = True
        elif name == 'select':
            print(f'Selected: {MENU[cursor]}')

    init_buttons()

    try:
        while True:
            poll(on_button)
            if dirty:
                render(device, MENU, cursor, scroll)
                dirty = False
            time.sleep(0.02)
    except KeyboardInterrupt:
        pass
    finally:
        device.cleanup()
        cleanup()


if __name__ == '__main__':
    main()
