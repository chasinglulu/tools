#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# (C) Copyright 2024 Charley <wangkart@aliyun.com>
#

CURRENT_PATH=$(cd "$(dirname "$0")";pwd)

function create_image()
{
	qemu-img create $IMG_NAME $IMG_SIZE
}

function make_partition()
{
	echo "============Begin to make partition for $IMG_NAME"
set -x
	# GPT partition table
	sudo parted $IMG_NAME mktable gpt
	# msic part 512KiB
	sudo parted $IMG_NAME mkpart misc 2MiB 2.5MiB
	# ubootenv part 512KiB
	sudo parted -s -a none $IMG_NAME mkpart ubootenv 2.5MiB 3MiB
	# vbmeta_a part 512KiB
	sudo parted -s -a none $IMG_NAME mkpart vbmeta_a 3MiB 3.5MiB
	# vbmeta_b part 512KiB
	sudo parted -s -a none $IMG_NAME mkpart vbmeta_b 3.5MiB 4MiB
        # spl_a part 2MiB
        sudo parted -s -a none $IMG_NAME mkpart spl_a 4MiB 6MiB
        # spl_b part 2MiB
        sudo parted -s -a none $IMG_NAME mkpart spl_b 6MiB 8MiB
        # atf_a part 512KiB
        sudo parted -s -a none $IMG_NAME mkpart atf_a 8MiB 8.5MiB
        # atf_b part 512KiB
        sudo parted -s -a none $IMG_NAME mkpart atf_b 8.5MiB 9MiB
        # optee_a part 512KiB
        sudo parted -s -a none $IMG_NAME mkpart optee_a 9MiB 9.5MiB
        # optee_b part 512KiB
        sudo parted -s -a none $IMG_NAME mkpart optee_b 9.5MiB 10MiB
        # uboot_a part 2MiB
        sudo parted -s -a none $IMG_NAME mkpart uboot_a 10MiB 12MiB
        # uboot_b part 2MiB
        sudo parted -s -a none $IMG_NAME mkpart uboot_b 12MiB 14MiB
	# boot_a partition 150MiB
	sudo parted -s -a none $IMG_NAME mkpart boot_a 14MiB 154MiB
	# boot_b partition 150MiB
	sudo parted -s -a none $IMG_NAME mkpart boot_b 154MiB 294MiB
	sudo parted $IMG_NAME set 13 boot on
	sudo parted $IMG_NAME set 14 boot on
	# rootfs partition 512MiB
	sudo parted -s -a none $IMG_NAME mkpart buildroot 304MiB 816MiB
	# userdata partition 512MiB
	sudo parted -s -a none $IMG_NAME mkpart userdata 816MiB 2040MiB
	sync

	part_map=$(sudo kpartx -av $IMG_NAME)

	# format filesystem
	sudo mkfs.vfat /dev/mapper/$(echo "$part_map" | sed -n '13p' | awk '{print $3}')
	sync

	sudo mkfs.vfat /dev/mapper/$(echo "$part_map" | sed -n '14p' | awk '{print $3}')
	sync
	sudo mkfs.ext4 /dev/mapper/$(echo "$part_map" | sed -n '15p' | awk '{print $3}')
	sync
	sudo tune2fs -f -O ^metadata_csum /dev/mapper/$(echo "$part_map" | sed -n '15p' | awk '{print $3}')
	sync

set +x

	echo "=============Successfully make partition"
}

function clean()
{
	sudo kpartx -dv $IMG_NAME
}

function main()
{
	create_image
	make_partition
	clean
}

function usage()
{
	echo "Usage:"
	echo "$0 -n <image name> -s <image size>"
}

if [ $# -lt 2 ]
then
    usage
    exit 1
fi

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
            usage
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))

main
