#! /bin/bash

CUR_DIR=$(cd $(dirname "$0");pwd)
IMAGE_DIR=""
DEVICE=""
TYPE=""

#itop4412 images name
BL1_FWBL_IMG="itop4412-fwbl.bin"
BL1_SPL_IMG="itop4412-spl.bin"
BL2_UBOOT_IMG="itop4412-u-boot.bin"
TZSW_IMG="itop4412-tzsw.bin"
ENV_IMG="itop4412-env.bin"

#itop4412 images position
BL1_FWBL_POS=1
BL1_SPL_POS=17
BL2_UBOOT_POS=49
TZSW_POS=1073
ENV_POS=1385

function usage()
{
    echo "Usage:"
	echo "    $(basename $0) [-d /dev/sdX] [-i /path/to/images/] [-t board]"
    echo "    -d /dev/sdX to specify block device file for sd card"
    echo "    -i /path/to/images/ to specify image direction, optional"
    echo "    -t board  to specify the kind of board"
    echo "For example:"
    echo "    $(basename $0) -d /dev/sdc -i ~/itop4412-images/ -t itop4412"
}

function bl1_fwbl_fusing()
{
    echo "BL1_FWBL fusing ..."
    dd iflag=dsync oflag=dsync if=$IMAGE_DIR/$BL1_FWBL_IMG of=$DEVICE seek=$BL1_FWBL_POS
    echo "Finish fusing BL1_FWBL image."
}

function bl1_spl_fusing()
{
    echo "BL1_SPL fusing ..."
	dd iflag=dsync oflag=dsync if=$IMAGE_DIR/$BL1_SPL_IMG of=$DEVICE seek=$BL1_SPL_POS
	echo "Finish fusing BL1_SPL image."
}

function bl2_uboot_fusing()
{
    echo "BL2_UBOOT fusing ..."
    dd iflag=dsync oflag=dsync if=$IMAGE_DIR/$BL2_UBOOT_IMG of=$DEVICE seek=$BL2_UBOOT_POS
    echo "Finish fusing BL2_UBOOT image."
}

function tzsw_fusing()
{
    echo "TZSW fusing ..."
    dd iflag=dsync oflag=dsync if=$IMAGE_DIR/$TZSW_IMG of=$DEVICE seek=$TZSW_POS
    echo "Finish fusing TZSW image."
}

function env_fusing()
{
    echo "ENV fusing ..."
    dd iflag=dsync oflag=dsync if=$IMAGE_DIR/$ENV_IMG of=$DEVICE seek=$ENV_POS
    echo "Finish fusing ENV image."
}

function main()
{
    echo "--------------------------[Begin]--------------------------"
    echo "May take a few minutes, wait ..."
    bl1_fwbl_fusing
    bl1_spl_fusing
    bl2_uboot_fusing
    tzsw_fusing
    env_fusing
    echo "--------------------------[End]----------------------------"
}

if [ $# -le 0 ] || [ $# -ge 7 ]
then
    echo "arguments too few or many."
    usage $0
    exit 1
fi

while getopts :ht:d:i:f: opt
do
    case $opt in
        'h')
            usage $0
            exit 0
            ;;
        't')
            TYPE="$OPTARG"
            ;;
        'd')
            if [ ! -b "$OPTARG" ]
            then
                echo "[$DEVICE] is NOT block device"
                exit 2
            fi
            DEVICE="$OPTARG"
            ;;
        'f')
            DEVICE="$OPTARG"
            ;;
        'i')
            IMAGE_DIR="$OPTARG"
            ;;
        ?)
            echo "unknown option [-$OPTARG]"
            usage $0
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "$DEVICE" ]
then
    echo "Failed to specify device or file"
    usage $0
    exit 0
fi

if [ -z "$IMAGE_DIR" ]
then
    IMAGE_DIR="$CUR_DIR"
fi

if [ ! -b "$DEVICE" ]
then
    echo "$DEVICE is NOT block device."
    dd if=/dev/zero of=$DEVICE bs=512 count=2048
    BL1_FWBL_POS=0
    BL1_SPL_POS=16
    BL2_UBOOT_POS=48
    TZSW_POS=1072
    ENV_POS=1384
fi

main
sync;sync;sync

