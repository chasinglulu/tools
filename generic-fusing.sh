#!/bin/bash

CUR_DIR=$(cd $(dirname "$0");pwd)
IMAGE_DIR=""
DEVICE=""
TYPE=""

IMG_NAME=(fwbl spl u-boot tzsw env)
IMG_POS=(1 17 49 1073 1385)
ITOP4412_POS=(1 17 49 1073 1385)
X4412_POS=(1 31 63 1099 1480)

function fusing()
{
	for i in {0..4}
	do
		echo -e "\n${IMG_NAME[$i]} fusing ..."
		dd iflag=dsync oflag=dsync if=$IMAGE_DIR/${IMG_NAME[$i]} of=$DEVICE seek=${IMG_POS[$i]}
		echo "Finish fusing ${IMG_NAME[$i]} image."
	done
}

function arguments_check()
{
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

	if [ "$TYPE" = "itop4412" ] || [ "$TYPE" = "x4412" ]
	then
		for i in {0..4}
		do
			IMG_NAME[$i]="$TYPE-${IMG_NAME[$i]}.bin"
			if [ "$TYPE" = "x4412" ]
			then
				IMG_POS[$i]=${X4412_POS[$i]}
			else
				IMG_POS[$i]=${ITOP4412_POS[$i]}
			fi
		done
	else
		echo "unknown board"
		usage $0
		exit 0
	fi

	if [ ! -b "$DEVICE" ]
	then
    		echo "$DEVICE is NOT block device."
		for i in {0..4}
		do
			IMG_POS[$i]=$((${IMG_POS[$i]} - 1))
		done
    		dd if=/dev/zero of=$DEVICE bs=512 count=2048
	fi
}

function main()
{
    echo "--------------------------[Begin]--------------------------"
    echo "May take a few minutes, wait ..."
	fusing
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

arguments_check $0
main
sync;sync;sync
