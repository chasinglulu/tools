#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# (C) Copyright 2023 Horizone Co., Ltd
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
	sudo parted $IMG_NAME mkpart misc 2048KiB 2559KiB
	# ubootenv part 512KiB
	sudo parted -s -a none $IMG_NAME mkpart ubootenv 2560KiB 3071KiB
	# vbmeta_a part 512KiB
	sudo parted -s -a none $IMG_NAME mkpart vbmeta_a 3072KiB 3583KiB
	# vbmeta_b part 512KiB
	sudo parted -s -a none $IMG_NAME mkpart vbmeta_b 3584KiB 4095KiB
	# boot_a partition 150MiB
	sudo parted -s -a none $IMG_NAME mkpart boot_a 4MiB 154MiB
	# boot_b partition 150MiB
	sudo parted -s -a none $IMG_NAME mkpart boot_b 154MiB 304MiB
	sudo parted $IMG_NAME set 5 boot on
	sudo parted $IMG_NAME set 6 boot on
	# userdata partition 923MiB
	sudo parted -s -a none $IMG_NAME mkpart userdata 304MiB 2046MiB
	sync

	part_map=$(sudo kpartx -av $IMG_NAME)

	# format filesystem
	sudo mkfs.vfat /dev/mapper/$(echo "$part_map" | sed -n '5p' | awk '{print $3}')
	sync

	sudo mkfs.vfat /dev/mapper/$(echo "$part_map" | sed -n '6p' | awk '{print $3}')
	sync
	sudo mkfs.ext4 /dev/mapper/$(echo "$part_map" | sed -n '7p' | awk '{print $3}')
	sync
	sudo tune2fs -f -O ^metadata_csum /dev/mapper/$(echo "$part_map" | sed -n '7p' | awk '{print $3}')
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
