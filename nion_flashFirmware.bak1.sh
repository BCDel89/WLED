#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m' # Reset color

# Query available USB serial devices
echo -e "${CYAN}Available USB serial devices:${RESET}"
devices=($(ls /dev/cu.* | grep -E "/dev/cu.(usbserial|usbmodem|SLAB_USBtoUART|wchusbserial)"))
if [ ${#devices[@]} -eq 0 ]; then
  echo -e "${RED}No USB serial devices found. Exiting.${RESET}"
  exit 1
fi

# Display the list of devices
for i in "${!devices[@]}"; do
  echo -e "${YELLOW}[$i] ${devices[$i]}${RESET}"
done

# Prompt the user to select a device
read -p "$(echo -e ${GREEN}Select a device by number:${RESET} ) " selection
if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -ge "${#devices[@]}" ]; then
  echo -e "${RED}Invalid selection. Exiting.${RESET}"
  exit 1
fi

# Set the selected device
selected_device="${devices[$selection]}"
echo -e "${BLUE}Selected device: $selected_device${RESET}"

# Source environment variables
source export.sh

# Build firmware and filesystem
# pio run -e esp32s3mini_4MB_psram
# pio run -e esp32s3mini_4MB_psram -t buildfs

# Prompt user to put the board in download mode
echo -e "${CYAN}You should put your board in download mode before flashing the firmware.${RESET}"
read -n 1 -s -r -p "$(echo -e ${GREEN}Press any key to acknowledge and continue...${RESET})"

# Flash the firmware using esptool.py
esptool.py --chip esp32s3 --baud 460800 \
  --port "$selected_device" \
  write_flash -z --flash_mode dio --flash_size 4MB \
  0x0      "$BOOTLOADER" \
  0x8000   .pio/build/esp32s3mini_4MB_psram/partitions.bin \
  0xe000   "$BOOTAPP0" \
  0x10000  .pio/build/esp32s3mini_4MB_psram/firmware.bin

# Prompt user to put the board in download mode again for filesystem upload
echo -e "${CYAN}You should put your board in download mode again before uploading the filesystem.${RESET}"
read -n 1 -s -r -p "$(echo -e ${GREEN}Press any key to acknowledge and continue...${RESET})"

# Upload the filesystem
# pio run -e esp32s3mini_4MB_psram -t uploadfs --upload-port "$selected_device"
pio run -e esp32s3mini_4MB_psram -t uploadfs --disable-auto-clean --upload-port "$selected_device"

