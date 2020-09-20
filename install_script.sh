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
  g # make a gpt table
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
  +1G # 2GB EFI+Boot partition
  t # change type
  2 # of partition 2
  1 # to 'EFI System'
  n #### new partition
  p # primary partition
  3 # partition number 3
    # default - start after Boot partition
    # default - fill all free space
  p # print the in-memory partition table
  w # write the partition table
  q # and we're done
EOF

# Format the EFI/Boot partition
mkfs.fat -F 32 /dev/nvme0n1p2

# Install ZFS utils
curl -s https://eoli3n.github.io/archzfs/init | bash

# Make a ZFS pool
zpool create -f -o ashift=9               \
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
		-O encryption=aes-256-gcm \
		-O keyformat=passphrase   \
		-O keylocation=prompt     \
                zroot /dev/disk/by-id/nvme-SAMSUNG*-part2

# Create ZFS datasets
zfs create -o mountpoint=none zroot/data
zfs create -o mountpoint=none zroot/ROOT
zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/default
zfs create -o mountpoint=/home zroot/data/home

# Validate ZFS config
zpool export zroot
zpool import -d /dev/disk/by-id -R /mnt zroot -N

# Make root locatable
zpool set bootfs=zroot/ROOT/default zroot

# Remove dir kindly but unnesserarily created by zfs-util
rmdir /mnt/home

# Mount partitions
zfs mount zroot/ROOT/default
zfs mount -a
mkdir /mnt/boot
mount /dev/nvme0n1p2 /mnt/boot

# Install essential packages
pacstrap /mnt base linux linux-firmware vim refind efibootmgr

# Copy cache
zpool set cachefile=/etc/zfs/zpool.cache zroot
mkdir /mnt/etc/zfs
cp /etc/zfs/zpool.cache /mnt/etc/zfs/zpool.cache

# Generate /etc/fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# Configure system
ln -sf /mnt/usr/share/zoneinfo/Europe/Zurich /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc
echo "KEYMAP=de_CH-latin1" > /mnt/etc/vconsole.conf

# Configure locale
sed -i '/en_US.UTF-8 UTF-8/s/^#//g' /mnt/etc/locale.gen
sed -i '/de_CH.UTF-8 UTF-8/s/^#//g' /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
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
arch-chroot /mnt pacman -Sy --noconfirm zfs-linux

# Edit mkinitcpio hooks
hooks='HOOKS=(base udev autodetect keyboard keymap consolefont modconf block zfs filesystems fsck)'
sed -i "/HOOKS=/c$hooks" /mnt/etc/mkinitcpio.conf

# Regenerate initramfs
arch-chroot /mnt mkinitcpio -P

# Bind system directories
mount --rbind /sys /mnt/sys
mount --rbind /proc /mnt/proc
mount --rbind /dev /mnt/dev

# Install rEFInd (for EFI)
chroot /mnt refind-install

# Set root password
chroot /mnt passwd

# Unmount stuff
umount /mnt/efi
umount -R /mnt/sys
umount -R /mnt/proc
umount -R /mnt/dev
zfs umount -a
zpool export zroot
umount -R /mnt

# TODO cryptboot?

# Finish message
echo "DONE! You may restart now."
