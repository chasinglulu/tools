#! /bin/bash
#
# ubuntu-minimal-18.04-itop4412.img 1G
#
# 依赖的工具：
# util-linux kpartx dosfstools e2fsprogs qemu-utils gddrescue


CURRENT_PATH=$(cd "$(dirname "$0")";pwd)

function create_image()
{
	qemu-img create $IMG_NAME $IMG_SIZE
}

function make_partition()
{
	# GPT partition table
	parted $IMG_NAME mktable gpt
	# vfat partition 100MiB
	parted $IMG_NAME mkpart fat32 1MiB 101MiB BOOT
	# ext4 partition 923MiB
	parted $IMG_NAME mkpart ext4 101MiB 1024MiB ROOTFS
	
	kpartx -av $IMG_NAME
	
	# format filesystem
	mkfs.vfat /dev/mapper/loop0p1
	mkfs.ext4 /dev/mapper/loop0p2
}

function flash_uboot()
{
	dd of=/dev/loop0 if=u-boot.bin bs=512 seek=1 conv=fsync
}

function make_boot()
{
	mount /dev/mapper/loop0p1 /mnt
}

function make_rootfs()
{
	mount /dev/mapper/loop0p2 /mnt
}

function clean()
{
	kpartx -dv $IMG_NAME
}

function main()
{
	create_image
	make_partition
	flash_uboot
	make_boot
	make_rootfs
	clean
}

while getopts :n:s: opt
do
	case $opt in
		n)
			IMG_NAME="$OPTARG"
			;;
		s)
			IMG_SIZE="$OPTARG"
			;;
		?)
			echo -e "\n[ERROR]$0: invaild option -$OPTARG\n" >&2
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))

main