#!/bin/bash

# This is an arch linux installation script, intended to do my system installation.
# You can use it yourself, but you'll probably have to customize it a bit.

# Fail on error
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

# Set keyboard map to swiss german
loadkeys de_CH-latin1

# Update system clock
timedatectl set-ntp true

# Partition the disk
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk /dev/nvme0n1
  o # clear the in memory partition table
  n #### new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk 
  +1M # 1MB BIOS Boot for GRUB
  t # change type
  1 # for partition number 1
  4 # to 'BIOS Boot'
  n # new partition
  p # primary partition
  2 # partion number 2
    # default, start immediately after preceding partition
  +1G # 1GB EFI partition (This is probably overkill, but better be safe than sorry)
  t # change type
  2 # of partition 2
  1 # to 'EFI System'
  n #### new partition
  p # primary partition
  3 # partition number 3
    # default - start after BIOS Boot partition
    # default - fill all free space
  p # print the in-memory partition table
  w # write the partition table
  q # and we're done
EOF

# Format the EFI partition
mkfs.fat -F 32 /dev/nvme0n1p2

# Encrypt the root partition (asks for a password)
cryptsetup luksFormat --type luks1 /dev/nvme0n1p3

# Open it (asks again)
cryptsetup open /dev/nvme0n1p3 crypt

# Install ZFS utils
curl -s https://eoli3n.github.io/archzfs/init | bash

# Make a ZFS pool
zpool create -d -f -o feature@allocation_classes=enabled \
                   -o feature@async_destroy=enabled      \
                   -o feature@bookmarks=enabled          \
                   -o feature@embedded_data=enabled      \
                   -o feature@empty_bpobj=enabled        \
                   -o feature@enabled_txg=enabled        \
                   -o feature@extensible_dataset=enabled \
                   -o feature@filesystem_limits=enabled  \
                   -o feature@hole_birth=enabled         \
                   -o feature@large_blocks=enabled       \
                   -o feature@lz4_compress=enabled       \
                   -o feature@project_quota=enabled      \
                   -o feature@resilver_defer=enabled     \
                   -o feature@spacemap_histogram=enabled \
                   -o feature@spacemap_v2=enabled        \
                   -o feature@userobj_accounting=enabled \
                   -o feature@zpool_checkpoint=enabled   \
		   -o ashift=9                           \
                   -O acltype=posixacl       \
                   -O relatime=on            \
                   -O xattr=sa               \
                   -O dnodesize=legacy       \
                   -O normalization=formD    \
                   -O mountpoint=none        \
                   -O canmount=off           \
                   -O devices=off            \
                   -R /mnt                   \
                   -O compression=lz4        \
                   zroot /dev/disk/by-id/dm-uuid-CRYPT-LUKS1-*

# Create ZFS datasets
zfs create -o mountpoint=none zroot/data
zfs create -o mountpoint=none zroot/BOOT
zfs create -o mountpoint=none zroot/ROOT
zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/default
zfs create -o mountpoint=/boot -o canmount=on zroot/BOOT/default
zfs create -o mountpoint=/home zroot/data/home

# Validate ZFS config
zpool export zroot
zpool import -d /dev/disk/by-id -R /mnt zroot -N

# Make root locatable
zpool set bootfs=zroot/ROOT/default zroot

# Remove dirs kindly but unnesserarily created by zfs-util
rmdir /mnt/home
rmdir /mnt/boot

# Mount partitions
zfs mount zroot/ROOT/default
zfs mount -a
mkdir /mnt/efi
mount /dev/nvme0n1p2 /mnt/efi

# Install essential packages
pacstrap /mnt base linux linux-firmware vim grub efibootmgr

# Copy cache
zpool set cachefile=/etc/zfs/zpool.cache zroot
mkdir /mnt/etc/zfs
cp /etc/zfs/zpool.cache /mnt/etc/zfs/zpool.cache

# Generate /etc/fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# Configure system
ln -sf /mnt/usr/share/zoneinfo/Europe/Zurich /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
echo "KEYMAP=de_CH-latin1" > /mnt/etc/vconsole.conf

# Configure locale
sed -i '/en_US.UTF-8 UTF-8/s/^#//g' /mnt/etc/locale.gen
sed -i '/de_CH.UTF-8 UTF-8/s/^#//g' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen

# Network configuration
echo -n "Hostname: "; read hostname
echo $hostname > /mnt/etc/hostname
cat > /mnt/etc/hosts << EOF
127.0.0.1	localhost
::1		localhost
127.0.1.1	$hostname.localdomain	$hostname
EOF

# Add ZFS repos to pacman
cat >> /mnt/etc/pacman.conf << 'EOF'
[archzfs]
# Origin Server - France
Server = http://archzfs.com/$repo/x86_64
# Mirror - Germany
Server = http://mirror.sum7.eu/archlinux/archzfs/$repo/x86_64
# Mirror - Germany
Server = https://mirror.biocrafting.net/archlinux/archzfs/$repo/x86_64
# Mirror - India
Server = https://mirror.in.themindsmaze.com/archzfs/$repo/x86_64

[archzfs-kernels]
Server = http://end.re/$repo/
EOF

# Chroot
arch-chroot /mnt pacman -Sy zfs-linux

# Edit mkinitcpio hooks
hooks='HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt zfs filesystems fsck)'
sed -i "/HOOKS=/c$hooks" /mnt/etc/mkinitcpio.conf

# Regenerate initramfs
arch-chroot /mnt mkinitcpio -P

# Use the faker script for grub-probe
#mv /mnt/bin/grub-probe /mnt/bin/grub-probe.orig
#cp grub-probe /mnt/bin
#chmod +x /mnt/bin/grub-probe
#chmod +x /mnt/bin/grub-probe.orig

# Bind system directories
mount --bind /sys /mnt/sys
mount --bind /proc /mnt/proc
mount --bind /dev /mnt/dev

# Install GRUB (for EFI)
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --recheck

# GRUB sanity check
arch-chroot /mnt grub-probe /boot

# Configure GRUB
dev_uuid=$(find /dev/disk/by-uuid/ -lname "*/nvme0n1p3")
kernel_default_params='GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3"'
kernel_params="GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$dev_uuid:crypt root=ZFS=zroot/ROOT/default\""
sed -i "/GRUB_CMDLINE_LINUX_DEFAULT/c$kernel_default_params" /mnt/etc/default/grub
sed -i "/GRUB_CMDLINE_LINUX/c$kernel_params" /mnt/etc/default/grub
cat >> /mnt/etc/default/grub << 'EOF'
GRUB_ENABLE_CRYPTODISK=y
GRUB_TERMINAL_OUTPUT=console
EOF
ZPOOL_VDEV_NAME_PATH=1 
mkdir /mnt/boot/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Configure grub.cfg
cat >> /mnt/boot/grub/grub.cfg << 'EOF'
set timeout=5
set default=0

menuentry "Arch Linux" {
    search -u UUID
    linux /ROOT/default/@/boot/vmlinuz-linux zfs=zroot/ROOT/default rw
    initrd /ROOT/default/@/boot/initramfs-linux.img
}
EOF

# Unmount stuff
umount /mnt/efi
zfs umount -a
zpool export zroot
umount -R /mnt

# TODO cryptboot?

# Set root password
arch-chroot /mnt passwd

# Finish message
echo "DONE! You may restart now."
