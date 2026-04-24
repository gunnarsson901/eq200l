import serial, time

PORT = '/dev/ttyUSB0'

print('=== Test 1: DTR/RTS reset then AT @ 9600 ===')
s = serial.Serial(PORT, 9600, timeout=2, dsrdtr=False, rtscts=False)
s.dtr = False
s.rts = False
time.sleep(0.1)
s.dtr = True
s.rts = True
time.sleep(0.5)
s.reset_input_buffer()
s.write(b'AT\r\n')
time.sleep(1)
print(f'  response: {repr(s.read_all())}')
s.close()

print('=== Test 2: DTR/RTS reset then AT @ 115200 ===')
s = serial.Serial(PORT, 115200, timeout=2, dsrdtr=False, rtscts=False)
s.dtr = False; s.rts = False; time.sleep(0.1)
s.dtr = True;  s.rts = True;  time.sleep(0.5)
s.reset_input_buffer()
s.write(b'AT\r\n')
time.sleep(1)
print(f'  response: {repr(s.read_all())}')
s.close()

print('=== Test 3: Raw bytes — listen for anything at 9600 for 5s ===')
s = serial.Serial(PORT, 9600, timeout=5)
s.dtr = True; s.rts = True
data = s.read(512)
print(f'  received: {repr(data)}')
s.close()

print('=== Test 4: Read raw at 115200 for 5s ===')
s = serial.Serial(PORT, 115200, timeout=5)
s.dtr = True; s.rts = True
data = s.read(512)
print(f'  received: {repr(data)}')
s.close()
