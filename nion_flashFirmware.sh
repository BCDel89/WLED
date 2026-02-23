#!/bin/bash
set -Eeuo pipefail

# =========================
# Config
# =========================
MAX_RETRIES=3
# BAUD=115200
BAUD=460800
VERBOSE=0   # set to 1 for extra logging

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
# Helpers
# =========================
die() {
  echo -e "${RED}[ERROR] $*${RESET}" >&2
  exit 1
}

log() {
  echo -e "${CYAN}[INFO] $*${RESET}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found"
}

# =========================
# Preflight checks
# =========================
require_cmd python3
require_cmd esptool.py
require_cmd pio

source export.sh

[[ -f "$BOOTLOADER" ]] || die "BOOTLOADER not found: $BOOTLOADER"
[[ -f "$BOOTAPP0" ]]   || die "BOOTAPP0 not found"
[[ -f ".pio/build/esp32s3mini_4MB_psram/firmware.bin" ]] || die "Firmware binary missing"

# =========================
# Enter download mode
# =========================
enter_download_mode() {
  local PORT="$1"

  python3 - <<EOF
import serial, time, sys
port="$PORT"

try:
    s = serial.Serial(port, 115200)
except Exception as e:
    print(f"[PY] Failed to open {port}: {e}")
    sys.exit(2)

# DTR -> GPIO0 (BOOT), RTS -> EN (RESET)
s.dtr = True        # BOOT LOW
time.sleep(0.05)
s.rts = True        # RESET LOW
time.sleep(0.15)
s.rts = False       # RESET HIGH
time.sleep(0.15)

# keep BOOT LOW until esptool connects
s.close()
EOF
}

release_boot() {
  local PORT="$1"
  python3 - <<EOF
import serial, time
s = serial.Serial("$PORT", 115200)
s.dtr = False       # BOOT HIGH
time.sleep(0.05)
s.close()
EOF
}

# =========================
# Find USB serial devices
# =========================
log "~ Finding USB serial devices"
devices=($(ls /dev/cu.* 2>/dev/null | grep -E "/dev/cu.(usbserial|usbmodem|SLAB_USBtoUART|wchusbserial)"))

[[ ${#devices[@]} -gt 0 ]] || die "No USB serial devices found"

if [[ ${#devices[@]} -eq 1 ]]; then
  selected_device="${devices[0]}"
  echo -e "${BLUE}Only one device found. Auto-selected: $selected_device${RESET}"
else
  echo -e "${CYAN}Available USB serial devices:${RESET}"
  for i in "${!devices[@]}"; do
    echo -e "${YELLOW}[$i] ${devices[$i]}${RESET}"
  done

  read -p "$(echo -e ${GREEN}Select a device by number:${RESET} ) " selection
  [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -lt "${#devices[@]}" ]] \
    || die "Invalid selection"

  selected_device="${devices[$selection]}"
fi

# Prefer tty.* on macOS (more reliable for modem control)
selected_device="${selected_device/cu./tty.}"
log "Using serial device: $selected_device"

# =========================
# Flash firmware with retries
# =========================
log "~ Flashing firmware with retries"
attempt=1
while [[ $attempt -le $MAX_RETRIES ]]; do
  log "Attempt $attempt/$MAX_RETRIES: entering download mode"
  enter_download_mode "$selected_device"

  if esptool.py --chip esp32s3 --baud "$BAUD" \
    --port "$selected_device" \
    --before no_reset --after no_reset \
    write_flash -z --flash_mode dio --flash_size 4MB \
      0x0      "$BOOTLOADER" \
      0x8000   .pio/build/esp32s3mini_4MB_psram/partitions.bin \
      0xe000   "$BOOTAPP0" \
      0x10000  .pio/build/esp32s3mini_4MB_psram/firmware.bin
  then
    log "Firmware flashed successfully"
    release_boot "$selected_device"
    break
  fi

  echo -e "${YELLOW}Flash attempt $attempt failed${RESET}"
  ((attempt++))
  sleep 0.5
done

[[ $attempt -le $MAX_RETRIES ]] || die "Failed to connect to ESP32-S3 after $MAX_RETRIES attempts (not in download mode?)"

# =========================
# Filesystem upload
# =========================
log "Uploading filesystem"
enter_download_mode "$selected_device"

pio run -e esp32s3mini_4MB_psram \
  -t uploadfs \
  --disable-auto-clean \
  --upload-port "$selected_device" \
  || die "Filesystem upload failed"

release_boot "$selected_device"

log "${GREEN}All done — flash + filesystem successful${RESET}"

