#!/bin/bash

CUR_DIR=$(cd $(dirname $0);pwd)
#URL="http://cdimage.ubuntu.com/ubuntu-base/releases/20.04.4/release/"
#URL="http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/"
#UBUNTU_BASE="ubuntu-base-20.04.3-base-arm64.tar.gz"
#UBUNTU_BASE="ubuntu-base-22.04-base-arm64.tar.gz"
UBUNTU_BASE="ubuntu-base-18.04.5-base-arm64.tar.gz"
IMAGE_NAME="ubuntu-18.04.5-rootfs-cpio-aarch64.img"
#IMAGE_NAME="ubuntu-20.04.3-rootfs-cpio-aarch64.img"
#IMAGE_NAME="ubuntu-22.04-rootfs-cpio-aarch64.img"

# 在PC Ubuntu上安装依赖工具
sudo apt-get install qemu-user-static binfmt-support

# 下载 ubuntu base rootfs package
if [ ! -f "$CUR_DIR/$UBUNTU_BASE" ]
then
    wget http://cdimage.ubuntu.com/ubuntu-base/releases/18.04.2/release/$UBUNTU_BASE
#    wget $URL$UBUNTU_BASE
fi

# 创建一个2GiB rootfs image并格式化为ext4
if [ ! -f "$CUR_DIR/$IMAGE_NAME" ]
then
    dd if=/dev/zero of=$CUR_DIR/$IMAGE_NAME bs=1M count=1024 oflag=direct
    mkfs.ext4 $CUR_DIR/$IMAGE_NAME
fi

mkdir -p $CUR_DIR/rootfs
sudo mount -t ext4 $CUR_DIR/$IMAGE_NAME $CUR_DIR/rootfs/

# 将ubuntu base rootfs package解压到本地目录中
sudo tar -xzf $CUR_DIR/$UBUNTU_BASE -C $CUR_DIR/rootfs/
sudo cp $CUR_DIR/*.deb $CUR_DIR/rootfs/var/

# # copy依赖的工具和host网络配置
sudo cp /usr/bin/qemu-aarch64-static $CUR_DIR/rootfs/usr/bin/
sudo cp /etc/resolv.conf $CUR_DIR/rootfs/etc/resolv.conf

# 挂载host proc、sys、dev等目录
sudo mount -t proc /proc $CUR_DIR/rootfs/proc
sudo mount -t sysfs /sys $CUR_DIR/rootfs/sys
sudo mount -o bind /dev $CUR_DIR/rootfs/dev
sudo mount -o bind /dev/pts $CUR_DIR/rootfs/dev/pts

# 配置ubuntu rootfs
sudo chroot $CUR_DIR/rootfs apt-get update
#sudo chroot $CUR_DIR/rootfs apt-get install dialog locales -y
sudo chroot $CUR_DIR/rootfs apt-get install sudo vim-tiny -y
sudo chroot $CUR_DIR/rootfs apt-get install net-tools iputils-ping -y
#sudo chroot $CUR_DIR/rootfs apt-get install udev -y
sudo chroot $CUR_DIR/rootfs apt-get install network-manager netplan.io systemd -y
sudo chroot $CUR_DIR/rootfs apt-get install kmod net-tools ifupdown -y
# sudo chroot $CUR_DIR/rootfs apt-get update
# sudo chroot $CUR_DIR/rootfs apt-get install dialog locales -y
# sudo chroot $CUR_DIR/rootfs apt-get install sudo vim bash-completion -y
# sudo chroot $CUR_DIR/rootfs apt-get install net-tools ethtool ifupdown iputils-ping -y
# sudo chroot $CUR_DIR/rootfs apt-get install rsyslog resolvconf udev -y
# sudo chroot $CUR_DIR/rootfs apt-get install network-manager netplan.io systemd -y
# sudo chroot $CUR_DIR/rootfs apt-get install openssh-server kmod parted -y
sudo chroot $CUR_DIR/rootfs /bin/bash -c "echo '
network:
  version: 2
  renderer: NetworkManager
' | sed '1d' >/etc/netplan/99-network.yaml"
sudo chroot rootfs sed -i '$d' /etc/netplan/99-network.yaml
PASSWD=$(mkpasswd "ubuntu")
sudo chroot $CUR_DIR/rootfs useradd -m -d /home/ubuntu -s /bin/bash -p $PASSWD "ubuntu"
sudo chroot $CUR_DIR/rootfs usermod -a -G sudo ubuntu
sudo chroot $CUR_DIR/rootfs /bin/bash -c "echo \"virt\" >/etc/hostname"
sudo chroot $CUR_DIR/rootfs /bin/bash -c "echo \"127.0.0.1 localhost\" >/etc/hosts"
sudo chroot $CUR_DIR/rootfs /bin/bash -c "echo \"127.0.0.1 virt\" >>/etc/hosts"

sudo chroot $CUR_DIR/rootfs mkdir -p /etc/systemd/system/serial-getty@ttyS1.service.d
sudo chroot $CUR_DIR/rootfs /bin/bash -c "echo '[Service]' >/etc/systemd/system/serial-getty@ttyS1.service.d/override.conf"
sudo chroot $CUR_DIR/rootfs /bin/bash -c "echo 'ExecStart=' >>/etc/systemd/system/serial-getty@ttyS1.service.d/override.conf"
STR="ExecStart=-/sbin/agetty -o \'-p -- \\\\u\' --keep-baud 921600,115200,38400,9600 --noclear --autologin root ttyS1 \\\$TERM"
sudo chroot $CUR_DIR/rootfs /bin/bash -c "echo $STR >>/etc/systemd/system/serial-getty@ttyS1.service.d/override.conf"
sudo chroot $CUR_DIR/rootfs sed -i '3a\auth sufficient pam_listfile.so item=tty sense=allow file=/etc/securetty onerr=fail apply=root' /etc/pam.d/login
sudo chroot $CUR_DIR/rootfs /bin/bash -c "echo ttyS1 > /etc/securetty"
sudo chroot $CUR_DIR/rootfs ln -s /lib/systemd/systemd init
sudo chroot $CUR_DIR/rootfs dpkg -i /var/linux-libc-dev_4.15.0-187.198_arm64.deb
sudo chroot $CUR_DIR/rootfs dpkg -i /var/libc6_2.28-0ubuntu1_arm64.deb
sudo chroot $CUR_DIR/rootfs dpkg -i /var/libc-dev-bin_2.28-0ubuntu1_arm64.deb
sudo chroot $CUR_DIR/rootfs dpkg -i /var/libc6-dev_2.28-0ubuntu1_arm64.deb
sudo chroot $CUR_DIR/rootfs dpkg -i /var/libc-bin_2.28-0ubuntu1_arm64.deb

#remove APT cache
set -x
sudo chroot $CUR_DIR/rootfs apt-get autoremove --yes
sudo chroot $CUR_DIR/rootfs apt-get clean
sudo chroot $CUR_DIR/rootfs apt-get autoclean
sudo chroot $CUR_DIR/rootfs /bin/bash -c "rm -rf /var/lib/apt/lists/ports.ubuntu.com_ubuntu-ports_dists_bionic*"
sudo chroot $CUR_DIR/rootfs rm -rf /var/cache/apt/*.bin
sudo chroot $CUR_DIR/rootfs /bin/bash -c "rm -rf /var/*.deb"
set +x

sudo umount $CUR_DIR/rootfs/proc
sudo umount $CUR_DIR/rootfs/sys
sudo umount $CUR_DIR/rootfs/dev/pts
sudo umount $CUR_DIR/rootfs/dev
sudo umount $CUR_DIR/rootfs/
rm -rf $CUR_DIR/rootfs
