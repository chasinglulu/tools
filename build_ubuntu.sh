#!/bin/bash

apt_mirror="http://localhost:3142/mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/"

#apt_mirror="http://localhost:3142/mirrors.tuna.tsinghua.edu.cn/ubuntu/"

dst_dir="hobot"
UBUNTU_MIRROR="mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/"
#UBUNTU_MIRROR="mirrors.tuna.tsinghua.edu.cn/ubuntu/"
DEBOOTSTRAP_LIST="systemd sudo vim locales apt-utils openssh-server ssh dbus init \
strace kmod init udev bash-completion netbase network-manager ethtool net-tools iputils-ping "

#DEBOOTSTRAP_LIST=" sudo"


ADD_PACKAGE_LIST="gcc file openssh-server ssh bsdmainutils whiptail device-tree-compiler \
bzip2 htop rsyslog make parted python3 python3-pip console-setup fake-hwclock \
ncurses-term gcc g++ i2c-tools toilet sysfsutils rsyslog tzdata u-boot-tools \
libcjson1 libcjson-dev db-util diffutils e2fsprogs iptables libc6 xterm \
libcrypt1 libcrypto++6 libdevmapper1.02.1 libedit2 libgcc-s1-arm64-cross libgcrypt20 libgpg-error0 \
libion0 libjsoncpp1 libkcapi1 libmenu-cache3 libnss-db libpcap0.8 libpcre3 \
libstdc++-10-dev libvorbis0a libzmq5 lvm2 makedev mtd-utils ncurses-term ncurses-base nettle-bin \
nfs-common openssl perl-base perl tftpd-hpa tftp-hpa tzdata watchdog tree \
wpasupplicant alsa-utils base-files cryptsetup diffutils dosfstools \
dropbear e2fsprogs ethtool exfat-utils ffmpeg file gdb gdbserver i2c-tools iperf3 iptables \
libaio1 libasound2 libattr1 libavcodec58 libavdevice58 libavfilter7 libavformat58 libavutil56 \
libblkid1 libc6 libc6-dev libcap2 libcom-err2 libcrypt-dev libdbus-1-3 libexpat1 libext2fs2 libflac8 \
libgcc1 libgdbm-compat4 libgdbm-dev libgdbm6 libgmp10 libgnutls30 libidn2-0 libjson-c4 libkmod2 \
liblzo2-2 libmount1 libncurses5 libncursesw5 libnl-3-200 libnl-genl-3-200 libogg0 libpopt0 \
libpostproc55 libreadline8 libsamplerate0 libsndfile1 libss2 libssl1.1 libstdc++6 libswresample3 \
libswscale5 libtinfo5 libtirpc3 libudev1 libunistring2 libusb-1.0-0 libuuid1 libwrap0 libx11-6 \
libxau6 libxcb1 libxdmcp6 libxext6 libxv1 libz-dev libz1 lrzsz lvm2 make mtd-utils net-tools \
netbase openssh-sftp-server openssl rpcbind screen sysstat tcpdump libgl1-mesa-glx \
thin-provisioning-tools trace-cmd tzdata usbutils watchdog libturbojpeg libturbojpeg0-dev \
xubuntu-desktop xserver-xorg-video-fbdev policykit-1-gnome notification-daemon tightvncserver "

#ADD_PACKAGE_LIST="gcc xubuntu-desktop xserver-xorg-video-fbdev policykit-1-gnome notification-daemon tightvncserver "
#ADD_PACKAGE_LIST="gcc aarch64-linux-gnu-gfortran "
#ADD_PACKAGE_LIST="gcc "

mount_chroot()
{
	local target=$1
	echo "Mounting" "$target" "info"
	mount -t proc chproc "${target}"/proc
	mount -t sysfs chsys "${target}"/sys
	mount -t devtmpfs chdev "${target}"/dev || mount --bind /dev "${target}"/dev
	mount -t devpts chpts "${target}"/dev/pts
}

create_sources_list()
{
	local release=$1
	local basedir=$2
	[[ -z $basedir ]] && echo "No basedir passed to create_sources_list" " " "err"
	# cp /etc/apt/sources.list "${basedir}"/etc/apt/sources.list
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
	#deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal main restricted universe multiverse
	deb http://${UBUNTU_MIRROR} $release main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} $release main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
	EOF
}

umount_chroot()
{
	local target=$1
	echo "Unmounting" "$target" "info"
	while grep -Eq "${target}.*(dev|proc|sys)" /proc/mounts
	do
		umount -l --recursive "${target}"/dev >/dev/null 2>&1
		umount -l "${target}"/proc >/dev/null 2>&1
		umount -l "${target}"/sys >/dev/null 2>&1
		sleep 5
	done
}

if [ ! -d $dst_dir/home ];then
	debootstrap --variant=minbase \
	--arch=arm64 \
	--include=${DEBOOTSTRAP_LIST// /,} \
	--verbose --no-merged-usr \
	--foreign focal \
	$dst_dir \
	$apt_mirror
	mkdir $dst_dir/usr/share/keyrings/
	cp /usr/bin/qemu-aarch64-static $dst_dir/usr/bin
	cp -a /usr/share/keyrings/*-archive-keyring.gpg $dst_dir/usr/share/keyrings/
	chroot ${dst_dir} /bin/bash -c "/debootstrap/debootstrap --second-stage"
fi

create_sources_list focal ${dst_dir}

mount_chroot $dst_dir

chroot $dst_dir bash -c "echo DU size:; cd /; du -sh"
apt_extra="-o Acquire::http::Proxy=\"http://localhost:3142\""
eval 'LC_ALL=C LANG=C chroot ${dst_dir} /bin/bash -c "apt-get -q -y $apt_extra update"'
eval 'LC_ALL=C LANG=C chroot ${dst_dir} /bin/bash -c "apt-get -q -y $apt_extra upgrade"'

#eval 'LC_ALL=C LANG=C chroot ${dst_dir} /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q  --no-install-recommends install $ADD_PACKAGE_LIST"'
#eval 'LC_ALL=C LANG=C chroot ${dst_dir} /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q  --no-install-recommends install ssh"'
#eval 'LC_ALL=C LANG=C chroot ${dst_dir} /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q $apt_extra --no-install-recommends install $ADD_PACKAGE_LIST"
ROOTPWD="root"
chroot "${dst_dir}" /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root"

eval 'LC_ALL=C LANG=C chroot ${dst_dir} /bin/bash -c "apt-get -q -y $apt_extra clean"'

umount_chroot $dst_dir

