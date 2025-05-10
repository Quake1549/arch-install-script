
# Arch Install Script

Automated Arch Linux installer with GNOME desktop environment and encrypted root support.

## Features

- UEFI with dedicated EFI partition (1 GiB)
- LUKS-encrypted root partition (optional)
- Swap partition (4 GiB)
- `systemd-boot` as the bootloader
- `ext4` filesystem for root
- User prompts for:
  - Time synchronization confirmation
  - Disk selection (`/dev/sda` or `/dev/nvme0n1`)
  - Root encryption
  - Hostname and username
- Parallel downloads enabled (`ParallelDownloads = 4` in `/etc/pacman.conf`)
- Installs essential packages:
  - `base`, `base-devel`, `nano`, `networkmanager`, `lvm2`, `cryptsetup`, `linux`, `linux-firmware`, `sudo`, `xorg-server`, `openssh`
- Installs **GNOME**:
  - `gnome`, `gnome-extra`, `gdm`
- Enables services:
  - `NetworkManager`, `gdm`, `sshd`
- Sets `graphical.target` as default

## Usage

Boot from the Arch Linux live ISO, connect to the internet, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/Quake1549/arch-install-script/main/arch-install.sh \
  -o arch-install.sh
chmod +x arch-install.sh
sudo ./arch-install.sh
```

Follow the interactive prompts to complete the installation.

## Post-Installation

After rebooting, log in with your user and GNOME should automatically launch via GDM.

---

*This script and instructions are maintained by **[Quake1549](https://github.com/Quake1549)**.*
