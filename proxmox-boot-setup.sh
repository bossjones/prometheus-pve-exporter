#!/bin/bash

# Script to detect EFI partition and configure proxmox-boot-tool
# Date: May 15, 2025

# Function to detect boot method
detect_boot_method() {
  echo "Detecting boot method..."

  if command -v efibootmgr &>/dev/null; then
    EFIBOOT_OUTPUT=$(efibootmgr -v 2>/dev/null)
    if [[ $? -eq 0 ]]; then
      echo "System is using UEFI boot"

      if [[ "$EFIBOOT_OUTPUT" =~ "proxmox" && "$EFIBOOT_OUTPUT" =~ "grubx64.efi" ]]; then
        echo "GRUB is used in UEFI mode"
        BOOT_METHOD="grub"
      elif [[ "$EFIBOOT_OUTPUT" =~ "systemd-bootx64.efi" ]]; then
        echo "systemd-boot is used"
        BOOT_METHOD="systemd-boot"
      else
        echo "Unknown UEFI boot loader, assuming GRUB"
        BOOT_METHOD="grub"
      fi
    else
      echo "EFI variables not supported, system likely using BIOS/Legacy mode"
      BOOT_METHOD="legacy"
    fi
  else
    echo "efibootmgr not found, cannot determine EFI boot method"
    BOOT_METHOD="unknown"
  fi

  return 0
}

# Function to find EFI system partition
find_efi_partition() {
  echo "Searching for EFI system partition..."

  # Method 1: Using blkid to find partitions with vfat and EFI type
  EFI_PARTS=$(lsblk -o NAME,FSTYPE,PARTTYPE,SIZE,MOUNTPOINT -p | grep -i 'vfat.*c12a7328-f81f-11d2-ba4b-00a0c93ec93b\|vfat.*EF00')

  if [[ -z "$EFI_PARTS" ]]; then
    # Method 2: Check for mounted EFI partitions
    EFI_PARTS=$(lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT -p | grep -i 'vfat.*/boot/efi')
  fi

  if [[ -z "$EFI_PARTS" ]]; then
    # Method 3: Look for partitions with EF type code
    EFI_PARTS=$(fdisk -l 2>/dev/null | grep -i 'EFI System')
  fi

  if [[ -n "$EFI_PARTS" ]]; then
    echo "Found EFI partition(s):"
    echo "$EFI_PARTS"

    # Extract the device name of the first EFI partition found
    EFI_DEV=$(echo "$EFI_PARTS" | head -n1 | awk '{print $1}')
    echo "Selected EFI partition: $EFI_DEV"
  else
    echo "No EFI partition found. System may be using legacy BIOS boot."
    EFI_DEV=""
  fi

  return 0
}

# Function to find boot disk
find_boot_disk() {
  echo "Detecting boot disk..."

  # Method 1: Find the device containing the root partition
  ROOT_PART=$(df -P / | tail -n 1 | awk '{print $1}')
  echo "Root partition is on: $ROOT_PART"

  # Method 2: Use lsblk to get parent kernel device name
  BOOT_DEV=$(eval $(lsblk -oMOUNTPOINT,PKNAME -P | grep 'MOUNTPOINT="/"'); echo $PKNAME | sed 's/[0-9]*$//')

  if [[ -n "$BOOT_DEV" ]]; then
    echo "Boot disk appears to be: /dev/$BOOT_DEV"
  else
    # Fallback: Extract disk name from root partition
    BOOT_DEV=$(echo $ROOT_PART | sed -E 's/p?[0-9]+$//' | sed -E 's/[0-9]+$//')
    echo "Boot disk (fallback method): $BOOT_DEV"
  fi

  return 0
}

# Function to check proxmox-boot-tool status
check_proxmox_boot_status() {
  echo "Checking proxmox-boot-tool status..."

  if command -v proxmox-boot-tool &>/dev/null; then
    PROXMOX_BOOT_STATUS=$(proxmox-boot-tool status 2>&1)
    echo "$PROXMOX_BOOT_STATUS"

    if [[ "$PROXMOX_BOOT_STATUS" =~ "No /etc/kernel/proxmox-boot-uuids found" ]]; then
      echo "proxmox-boot-tool is not configured for ESP synchronization"
      NEEDS_INIT=true
    else
      echo "proxmox-boot-tool is already configured"
      NEEDS_INIT=false
    fi
  else
    echo "proxmox-boot-tool not found"
    NEEDS_INIT=false
  fi

  return 0
}

# Function to initialize proxmox-boot-tool
initialize_proxmox_boot_tool() {
  if [[ "$NEEDS_INIT" == true && -n "$EFI_DEV" ]]; then
    echo "Preparing to initialize proxmox-boot-tool with EFI partition: $EFI_DEV"

    # Check if EFI partition is mounted
    EFI_MOUNT=$(lsblk -o NAME,MOUNTPOINT -n "$EFI_DEV" | awk '{print $2}')

    if [[ -n "$EFI_MOUNT" && "$EFI_MOUNT" != "" ]]; then
      echo "EFI partition is mounted at $EFI_MOUNT, unmounting first..."
      umount "$EFI_MOUNT"
    fi

    # Generate the command based on boot method
    if [[ "$BOOT_METHOD" == "grub" ]]; then
      INIT_CMD="proxmox-boot-tool init $EFI_DEV grub"
    else
      INIT_CMD="proxmox-boot-tool init $EFI_DEV"
    fi

    echo "Command to execute: $INIT_CMD"
    echo "To execute this command, run:"
    echo "$INIT_CMD"

    # Uncomment to actually run the command (caution!)
    # eval $INIT_CMD

    echo "After initialization, run 'mount -a' to remount all filesystems"
  elif [[ "$NEEDS_INIT" == true ]]; then
    echo "Cannot initialize proxmox-boot-tool: No EFI partition found"
  else
    echo "No initialization needed"
  fi

  return 0
}

# Main execution
echo "=== Proxmox Boot Tool Configuration Helper ==="
echo "Current date: $(date)"

detect_boot_method
find_efi_partition
find_boot_disk
check_proxmox_boot_status
initialize_proxmox_boot_tool

echo "=== Script completed ==="
echo "To refresh boot configuration after changes, run: proxmox-boot-tool refresh"
