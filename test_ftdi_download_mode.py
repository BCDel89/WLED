#!/usr/bin/env python3
import serial
import time
import sys

# PORT = "/dev/ttyUSB0"
PORT = "/dev/cu.usbserial-A5069RR4"
BAUD = 115200

print(f"[INFO] Opening serial port {PORT}...")

try:
    ser = serial.Serial(
        port=PORT,
        baudrate=BAUD,
        timeout=1
    )
except Exception as e:
    print(f"[FAIL] Could not open serial port: {e}")
    sys.exit(1)

print("[INFO] Serial port opened.")

# ESP32 auto-download sequence (Espressif standard)
# DTR -> GPIO0 (BOOT)
# RTS -> EN (RESET)
print("[INFO] Attempting to enter download mode...")

# Ensure both released
ser.dtr = False
ser.rts = False
time.sleep(0.1)

# Hold BOOT low
ser.dtr = True
time.sleep(0.1)

# Pulse RESET low
ser.rts = True
time.sleep(0.1)
ser.rts = False
time.sleep(0.1)

# Release BOOT
ser.dtr = False
time.sleep(0.2)

print("[INFO] Boot sequence complete, probing ESP...")

# Send sync bytes (same idea esptool uses)
ser.write(b"\x00" * 32)
time.sleep(0.2)

response = ser.read(64)

if response:
    print("[PASS] ESP responded — FTDI auto-download wiring looks correct!")
    print(f"[INFO] Raw response: {response.hex()}")
else:
    print("[FAIL] No response from ESP.")
    print("       This usually means BOOT/RESET wiring is incorrect.")
    print("       Double-check DTR → GPIO0 and RTS → EN.")

ser.close()

