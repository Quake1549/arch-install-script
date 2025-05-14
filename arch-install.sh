#!/usr/bin/env bash
set -euo pipefail

# Helper: ask yes/no (return 0 for yes, 1 for no)
ask_yes_no() {
    while true; do
        read -rp "$1 [y/n]: " yn
        case $yn in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

clear
echo "=== Arch Linux Automated Install (Encrypted Root) with GNOME ==="

# Step 1: Sync time (enable NTP)
echo "🔄 Enabling NTP for system clock..."
timedatectl set-ntp true
timezone=$(timedatectl show -p Timezone --value)
echo "Current timezone: $timezone"

# Step 2: Disk selection
echo -e "\n💽 Select disk for installation:"
echo "1) /dev/sda"
echo "2) /dev/nvme0n1"
read -rp "Enter choice [1/2]: " disk_choice
case "$disk_choice" in
    1) DISK="/dev/sda" ;;
    2) DISK="/dev/nvme0n1" ;;
    *) echo "Invalid selection."; exit 1 ;;
esac

# Confirm disk will be wiped
echo "⚠️  All data on $DISK will be destroyed!"
if ! ask_yes_no "Proceed with partitioning $DISK?"; then
    echo "Aborted."
    exit 1
fi

# Step 3: Partition disk
echo "🧱 Partitioning $DISK..."
wipefs -a "$DISK"
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 1025MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary linux-swap 1025MiB 5121MiB
parted -s "$DISK" mkpart primary ext4 5121MiB 100%

# Partition paths (NVMe vs SATA)
if [[ "$DISK" == *"nvme"* ]]; then
    EFI_PART="${DISK}p1"
    SWAP_PART="${DISK}p2"
    ROOT_PART="${DISK}p3"
else
    EFI_PART="${DISK}1"
    SWAP_PART="${DISK}2"
    ROOT_PART="${DISK}3"
fi
echo "EFI: $EFI_PART, SWAP: $SWAP_PART, ROOT: $ROOT_PART"

# Step 4: Format and mount
echo "🔧 Initializing swap..."
mkswap "$SWAP_PART"
swapon "$SWAP_PART"

echo "🔧 Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"
if ask_yes_no "Encrypt root partition ($ROOT_PART) with LUKS?"; then
    ENCRYPTED=true
    echo "🔐 Encrypting root partition..."
    cryptsetup luksFormat "$ROOT_PART"
    cryptsetup open "$ROOT_PART" cryptroot
    mkfs.ext4 /dev/mapper/cryptroot
    ROOT_MOUNT="/dev/mapper/cryptroot"
else
    ENCRYPTED=false
    echo "💾 Formatting root without encryption..."
    mkfs.ext4 "$ROOT_PART"
    ROOT_MOUNT="$ROOT_PART"
fi

mkdir -p /mnt
mount "$ROOT_MOUNT" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot
echo "✅ Partitions ready and mounted."

# Step 5: Optimize pacman
echo "⚙️ Tuning /etc/pacman.conf for faster downloads..."
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 4/' /etc/pacman.conf

# Step 6: Install base system and GNOME
echo "📦 Installing base system and GNOME desktop..."
pacstrap /mnt base base-devel nano networkmanager lvm2 cryptsetup linux linux-firmware sudo xorg-server gnome gdm openssh

# Step 7: Generate fstab
echo "📝 Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Step 8: Prompt user for hostname and username
while true; do
    read -rp "Enter hostname: " HOSTNAME
    [[ -n "$HOSTNAME" ]] && break
    echo "Hostname cannot be empty."
done
while true; do
    read -rp "Enter username: " USERNAME
    [[ -n "$USERNAME" ]] && break
    echo "Username cannot be empty."
done

# Step 9: System configuration inside chroot (hostname, locale, initramfs, bootloader, services)
echo "🔧 Configuring system in chroot..."
arch-chroot /mnt /bin/bash -e <<EOF
set -euo pipefail

# Set hostname
echo "$HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Time zone
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

# Locale
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Create user and allow sudo
useradd -m -G wheel,video,audio "$USERNAME"
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

# Prepare initramfs for encryption if needed
if [ $ENCRYPTED = true ]; then
    sed -i 's/block/& encrypt/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

# Install systemd-boot
bootctl --path=/boot install

# Configure bootloader entries
UUID=$(blkid -s UUID -o value $ROOT_PART)
if [ $ENCRYPTED = true ]; then
    cat <<LOADER > /boot/loader/loader.conf
default arch
timeout 5
editor 0
LOADER

    cat <<ENTRY > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options cryptdevice=UUID=$UUID:cryptroot root=/dev/mapper/cryptroot rw
ENTRY
else
    cat <<LOADER > /boot/loader/loader.conf
default arch
timeout 5
editor 0
LOADER

    cat <<ENTRY > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=$ROOT_PART rw
ENTRY
fi

# Enable services
systemctl enable NetworkManager
systemctl enable gdm
systemctl enable sshd
systemctl set-default graphical.target
EOF

# Step 10: Set root and user passwords
echo "🔐 Setting passwords for root and user..."
arch-chroot /mnt passwd
arch-chroot /mnt passwd "$USERNAME"

# Step 11: Confirm before reboot
if ask_yes_no "Installation complete. Reboot into the new system now?"; then
    echo "🚀 Unmounting and rebooting..."
    umount -R /mnt
    if [ "$ENCRYPTED" = true ]; then
        cryptsetup close cryptroot
    fi
    reboot
else
    echo "⚠️ Installation halted. Remember to unmount /mnt and reboot manually."
    exit 0
fi

