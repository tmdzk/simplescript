#!/bin/sh 

sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/g' /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
sed -i 's/enp1s0/eth0/g' /etc/network/interfaces

echo "auto eth1
iface eth1 inet static
address 10.0.2.1
netmask 255.255.255.0" > /etc/network/interfaces.d/eth1

reboot
