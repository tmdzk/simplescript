#!/bin/sh
# Setting up env variable, user and project path
MAGMA_ROOT="/home/magma"
MAGMA_USER="magma"
AGW_INSTALL_CONFIG="/etc/systemd/system/multi-user.target.wants/agw_installation.service"
AGW_SCRIPT_PATH="/root"
# Testing if the right Kernel Version is installed and $MAGMA_USER is sudoers
if [ ! -f "$AGW_SCRIPT_PATH/agw_install.sh" ]; then
  wget --no-cache -O $AGW_SCRIPT_PATH/agw_install.sh https://raw.githubusercontent.com/facebookincubator/magma/master/lte/gateway/deploy/agw_installation.sh
fi

if [ `uname -r` != "4.9.0-9-amd64" ] || ! grep -q "$MAGMA_USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then
  PING_SUCCESS="ok"
  # Testing that enp1s0 (eth0) is connected to the internet
  PING_RESULT=`ping -c 1 -I enp1s0 8.8.8.8 &> /dev/null && echo "$PING_SUCCESS"`
  if [[ "$PING_RESULT" != "$PING_SUCCESS" ]]; then
    echo "enp1s0 (eth0) is not connected to internet, please double check your plugged wires."
    exit 1
  fi
  # changing intefaces name
  sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/g' /etc/default/grub
  # changing interface name
  grub-mkconfig -o /boot/grub/grub.cfg
  sed -i 's/enp1s0/eth0/g' /etc/network/interfaces

  # configuring eth1
  echo "auto eth1
  iface eth1 inet static
  address 10.0.2.1
  netmask 255.255.255.0" > /etc/network/interfaces.d/eth1

  # As 4.9.0-9-amd64 has been removed from the current deb repo we're temporary using a snapshot
  if ! grep -q "deb http://snapshot.debian.org/archive/debian/20190801T025637Z" /etc/apt/sources.list; then
    echo "deb http://snapshot.debian.org/archive/debian/20190801T025637Z stretch main non-free contrib" >> /etc/apt/sources.list
  fi

  # Update apt
  apt update
  # Installing prerequesites
  apt install -y sudo python-minimal aptitude linux-image-4.9.0-9-amd64 linux-headers-4.9.0-9-amd64
  # Removing dev repository snapshot from source.list
  sed -i '/20190801T025637Z/d' /etc/apt/sources.list

  # Making magma a sudoer
  adduser $MAGMA_USER sudo
  echo "$MAGMA_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

  # Making sure .ssh is created in magma user
  mkdir -p /home/$MAGMA_USER/.ssh
  chown $MAGMA_USER:$MAGMA_USER /home/$MAGMA_USER/.ssh
  # Removing incompatible Kernel version
  apt remove -y linux-image-4.9.0-11-amd64
  chmod 644 $AGW_INSTALL_CONFIG
  # echo the the service config
  echo "[Unit]
Description=AGW Installation
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh /root/agw_install.sh
User=root
Group=root

[Install]
WantedBy=multi-user.target" > $AGW_INSTALL_CONFIG
  reboot
else
  echo "Right Kernel version is installed and magma is sudoers pursuing installation"
  apt-get update
  apt-get -y install curl make virtualenv zip rsync git software-properties-common python3-pip python-dev
  alias python=python3
  # Installing ansible.
  pip3 install ansible
  # Cloning magma.
  git clone https://github.com/facebookincubator/magma.git /home/$MAGMA_USER/magma
  # Setting up deploy path
  DEPLOY_PATH="/home/$MAGMA_USER/magma/lte/gateway/deploy"
  # Generating a localhost hostfile.
  echo "[ovs_build]
127.0.0.1 ansible_connection=local
[ovs_deploy]
127.0.0.1 ansible_connection=local" > $DEPLOY_PATH/agw_hosts
  # Triggering ovs_build in order to build custom patches.
  su - $MAGMA_USER -c "ansible-playbook -e \"MAGMA_ROOT='/home/$MAGMA_USER/magma' OUTPUT_DIR='/tmp'\" -i $DEPLOY_PATH/agw_hosts $DEPLOY_PATH/ovs_build.yml"
  # Triggering ovs_deploy in order deploy magma.
  su - $MAGMA_USER -c "ansible-playbook -e \"PACKAGE_LOCATION='/tmp'\" -i $DEPLOY_PATH/agw_hosts $DEPLOY_PATH/ovs_deploy.yml"
  # deleting boot script
  if [ -f "$AGW_INSTALL_CONFIG" ]; then
    rm -rf $AGW_INSTALL_CONFIG
  fi
  # removing ansible from the freshly installed agw
  pip3 uninstall --yes ansible
  # Final messages magma status and end message
  service magma@* status
  echo "AGW installation is done."
fi
