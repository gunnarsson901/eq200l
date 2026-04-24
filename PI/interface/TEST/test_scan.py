import lgpio, time

h = lgpio.gpiochip_open(0)
claimed = []
for p in range(28):
    try:
        lgpio.gpio_claim_input(h, p, lgpio.SET_PULL_UP)
        claimed.append(p)
    except Exception:
        pass

baseline = {p: lgpio.gpio_read(h, p) for p in claimed}
already_low = [p for p, v in baseline.items() if v == 0]
print(f'Monitoring {len(claimed)} GPIO pins. Already LOW: {already_low}')
print('Press and HOLD any button for 8 seconds...')

for i in range(26):
    changed = []
    for p in claimed:
        v = lgpio.gpio_read(h, p)
        if v != baseline[p]:
            changed.append(f'GPIO{p}={v}')
    if changed:
        print(f'{i:2d}: CHANGED -> {changed}')
    else:
        print(f'{i:2d}: no change')
    time.sleep(0.3)

lgpio.gpiochip_close(h)
