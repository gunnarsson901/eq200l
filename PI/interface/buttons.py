import lgpio

UP     = 20
DOWN   = 21
LEFT   = 13
RIGHT  = 26
SELECT = 16

ALL = {'up': UP, 'down': DOWN, 'left': LEFT, 'right': RIGHT, 'select': SELECT}

_h    = None
_last = {}


def init_buttons():
    global _h
    _h = lgpio.gpiochip_open(0)
    for pin in ALL.values():
        lgpio.gpio_claim_input(_h, pin, lgpio.SET_PULL_UP)
        _last[pin] = lgpio.gpio_read(_h, pin)


def poll(callback):
    for name, pin in ALL.items():
        state = lgpio.gpio_read(_h, pin)
        if state == 0 and _last[pin] == 1:
            callback(name)
        _last[pin] = state


def cleanup():
    if _h is not None:
        lgpio.gpiochip_close(_h)
