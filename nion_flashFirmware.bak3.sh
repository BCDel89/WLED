#!/bin/bash

# =========================
# Color codes
# =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# =========================
# Helper: enter ESP download mode via DTR/RTS
# =========================
enter_download_mode() {
  local PORT="$1"

  echo -e "${CYAN}Putting board into download mode automatically...${RESET}"

  python3 - <<EOF
import serial, time, sys

port = "$PORT"

try:
    s = serial.Serial(port, 115200)
except Exception as e:
    print(f"[ERROR] Could not open serial port {port}: {e}")
    sys.exit(1)

# Espressif auto-download sequence
s.dtr = False
s.rts = False
time.sleep(0.1)

s.dtr = True      # BOOT (GPIO0) LOW
time.sleep(0.1)

s.rts = True      # RESET (EN) LOW
time.sleep(0.1)
s.rts = False     # RESET HIGH
time.sleep(0.1)

s.dtr = False     # BOOT HIGH
time.sleep(0.2)

s.close()
EOF
}

# =========================
# Query available USB serial devices
# =========================
echo -e "${CYAN}Available USB serial devices:${RESET}"
devices=($(ls /dev/cu.* 2>/dev/null | grep -E "/dev/cu.(usbserial|usbmodem|SLAB_USBtoUART|wchusbserial)"))
if [ ${#devices[@]} -eq 0 ]; then
  echo -e "${RED}No USB serial devices found. Exiting.${RESET}"
  exit 1
fi

# Auto-select if only one device is found
if [ ${#devices[@]} -eq 1 ]; then
  selected_device="${devices[0]}"
  echo -e "${BLUE}Only one device found. Auto-selected: $selected_device${RESET}"
else
  # Display device list
  for i in "${!devices[@]}"; do
    echo -e "${YELLOW}[$i] ${devices[$i]}${RESET}"
  done

  # Prompt user to select device
  read -p "$(echo -e ${GREEN}Select a device by number:${RESET} ) " selection
  if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -ge "${#devices[@]}" ]; then
    echo -e "${RED}Invalid selection. Exiting.${RESET}"
    exit 1
  fi

  selected_device="${devices[$selection]}"
  echo -e "${BLUE}Selected device: $selected_device${RESET}"
fi

# =========================
# Source environment variables
# =========================
source export.sh

# =========================
# Build steps (intentionally disabled)
# =========================
# pio run -e esp32s3mini_4MB_psram
# pio run -e esp32s3mini_4MB_psram -t buildfs

# =========================
# AUTOMATIC download mode (firmware)
# =========================
enter_download_mode "$selected_device"

# =========================
# Flash firmware
# =========================
esptool.py --chip esp32s3 --baud 115200 \
  --port "$selected_device" \
  write_flash -z --flash_mode dio --flash_size 4MB \
  0x0      "$BOOTLOADER" \
  0x8000   .pio/build/esp32s3mini_4MB_psram/partitions.bin \
  0xe000   "$BOOTAPP0" \
  0x10000  .pio/build/esp32s3mini_4MB_psram/firmware.bin

# =========================
# AUTOMATIC download mode (filesystem)
# =========================
enter_download_mode "$selected_device"

# =========================
# Upload filesystem
# =========================
pio run -e esp32s3mini_4MB_psram \
  -t uploadfs \
  --disable-auto-clean \
  --upload-port "$selected_device"


