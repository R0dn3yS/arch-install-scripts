#!/bin/bash

# Clearing the TTY
clear

# Selecting a kernel to install
kernel_selector () {
	echo "List of kernels:"
	echo "1) Stable - Vanilla Linux kernel and modules, with a few patches applied."
	echo "2) Hardened - A security-focused Linux kernel."
	echo "3) Longterm - Long-term support (LTS) Linux kernel."
	echo "4) Zen Kernel - Optimized for desktop usage."
	read -r -p "Insert the number of the corresponding kernel: " choice
	echo "$choice will be installed"
	case $choice in
		1 ) kernel=linux
			;;
		2 ) kernel=linux-Hardened
			;;
		3 ) kernel=linux-lts
			;;
		4 ) kernel=linux-zen
			;;
		* ) echo "You did not enter a valid selection."
			kernel_selector
	esac
}

# Selecting a way to handle internet connection.
network_selector () {
	echo "Network utilities:"
	echo "1) IWD - iNet wireless daemon is a wireless daemon for Linux written by Intel (WiFI-only)."
	echo "2) NetworkManager - Program for providing detection and configuration for systems to automatically connect to networks (both WiFi and Ethernet)."
	echo "3) wpa_supplicant - It's a cross-platform supplicant with support for WEP, WPA and WPA2 (WiFi-only, a DHCP client will be automatically installed too.)"
	echo "4) I will do this on my own."
	read -r -p "Insert the number of the corresponding network utility: " choice
	echo "$choice will be installed"
	case $choice in
		1 ) echo "Installing IWD."
			pacstrap /mnt iwd
			echo "Enabling IWD."
			systemctl enable iwd --root=/mnt &>/dev/null
			;;
		2 ) echo "Installing NetworkManager."
			pacstrap /mnt networkmanager
			echo "Enabling NetworkManager."
			systemctl enable NetworkManager --root=/mnt &>/dev/null
			;;
		3 ) echo "Installing wpa_supplicant and dhcpcd."
			pacstrap /mnt wpa_supplicant dhcpcd
			echo "Enabling wpa_supplicant and dhcpcd."
			systemctl enable wpa_supplicant --root=/mnt &>/dev/null
			systemctl enable dhcpcd --root=/mnt &>/dev/null
			;;
		4 )
			;;
		* ) echo "You did not enter a valid selection."
			network_selector
	esac
}

de_selector () {
	echo "Desktop environment:"
	echo "1) XFCE"
	echo "2) Gnome"
	echo "3) Plasma"
	echo "4) I will do this on my own."
	read -r -p "Insert the number of the corresponding desktop environment: " choice
	echo "$choice will be installed"
	case $choice in
		1 ) echo "Installing XFCE."
			pacstrap /mnt xfce4 xfce4-goodies lightdm xorg
			echo "Enabling LightDM."
			systemctl enable lightdm --root=/mnt &>/dev/null
			;;
		2 ) echo "Installing Gnome."
			pacstrap /mnt gnome gdm xorg
			echo "Enabling GDM."
			systemctl enable gdm --root=/mnt &>/dev/null
			;;
		3 ) echo "Installing Plasma."
			pacstrap /mnt plasma-meta sddm xorg
			echo "Enabling SDDM."
			systemctl enable sddm --root=/mnt &>/dev/null
			;;
		4 )
			;;
		* ) echo "You did not enter a valid selection."
			de_selector
	esac
}

# Checking the microcode to install.
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ $CPU == *"AuthenticAMD"* ]]
then
	microcode=amd-ucode
else
	microcode=intel-ucode
fi

# Selecting the target for the new installation.
PS3="Select the disk where Arch Linux is going to be installed: "
select ENTRY in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd");
do
	DISK=$ENTRY
	echo "Installing Arch Linux on $DISK."
	break
done

# Deleting old partition scheme.
read -r -p "This will delete the current partition on $DISK. Do you agree [y/N]? " response
response=${response,,}
if [[ "$response" =~ ^(yes|y)$ ]]
then
	wipefs -af "$DISK" &>/dev/null
	sgdisk -Zo "$DISK" &>/dev/null
else
	echo "Quitting."
	exit
fi

# Creating a new partition scheme.
echo "Creating new partition scheme on $DISK."
parted -s "$DISK" \
	mklabel gpt \
	mkpart ESP fat32 1MiB 513MiB \
	set 1 esp on \
	mkpart BTRFS 513MiB 100% \

ESP="/dev/disk/by-partlabel/ESP"
BTRFS="/dev/disk/by-partlabel/BTRFS"

# Informing the kernel of the changes.
echo "Informing the kernel about the disk changes."
partprobe "$DISK"

# Formatting the ESP as FAT32.
mkfs.fat -f -F32 $ESP &>/dev/null

# Formatting the root partition as BTRFS.
mkfs.btrfs -f $BTRFS &>/dev/null

# Mounting partitions
mount $BTRFS /mnt
mkdir /mnt/efi
mount $ESP /mnt/efi

kernel_selector

# Pacstrap (setting up a base system onto the new root).
echo "Installing the base system (it may take a while)."
pacstrap /mnt base $kernel $microcode linux-firmware btrfs-progs grub grub-btrfs efibootmgr base-devel

network_selector
de_selector

# Checking if machine is vm
read -r -p "Is this machine a VM [y/N]? " response
response=${response,,}
if [[ "$response" =~ ^(yes|y)$ ]]
then
	echo "Installing Virtualbox guest utils."
	pacstrap /mnt virtualbox-guest-utils
	echo "Enabling vboxservice."
	systemctl enable vboxservice --root=/mnt &>/dev/null
fi

# Generating /etc/fstab.
echo "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Setting hostname.
read -r -p "Please enter the hostname: " hostname
echo "$hostname" > /mnt/etc/hostname

# Setting username.
read -r -p "Please enter name for a user account (enter empty to not create one): " username

# Setting up locales.
read -r -p "Please insert the locale you use (format: xx_XX): " locale
echo "$locale.UTF-8 UTF-8"  > /mnt/etc/locale.gen
echo "LANG=$locale.UTF-8" > /mnt/etc/locale.conf

# Setting hosts file.
echo "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

# Configuring the system.
arch-chroot /mnt /bin/bash -e <<EOF

	# Setting up timezone.
	ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime &>/dev/null

	# Setting up clock.
	hwclock --systohc
	# Generating locales.
	echo "Generating locales."
	locale-gen &>/dev/null
	# Installing GRUB.
	echo "Installing GRUB on /efi."
	grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB &>/dev/null

	# Creating grub config file.
	echo "Creating GRUB config file."
	grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
	# Adding user with sudo privilege
    echo "Adding $username with root privilege."
    useradd -m $username
    usermod -aG wheel $username
    echo "$username ALL=(ALL) ALL" >> /etc/sudoers.d/$username
EOF

# Setting root password.
echo "Setting root password."
arch-chroot /mnt /bin/passwd
[ -n "$username" ] && echo "Setting user password for ${username}." && arch-chroot /mnt /bin/passwd "$username"

# Finishing up
echo "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit