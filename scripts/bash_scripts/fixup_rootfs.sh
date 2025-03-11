#!/usr/bin/env bash

# Default values
WORKSPACE=""
PLATFORM=""

# Function to print usage
usage() {
    echo "Usage: $0 [-h] -w <workspace> -p <platform>"
    echo "  -h: Show help message"
    echo "  -w <workspace>: Specify the workspace directory"
    echo "  -p <platform>: Specify the platform"
    exit 1
}

# Parse command line options
while getopts "hw:p:" opt; do
    case $opt in
        w)
            WORKSPACE="$OPTARG"
            ;;
        p)
            PLATFORM="$OPTARG"
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Remove parsed options
shift $((OPTIND-1))

# Check if required arguments are provided
if [ -z "$WORKSPACE" ] || [ -z "$PLATFORM" ]; then
    echo "WORKSPACE and PLATFORM must be specified."
    usage
fi

CURR_DIR=$(cd $WORKSPACE/build;pwd)
ROOTFS_CPIO_LZ4=$WORKSPACE/build/out/$PLATFORM/objs/kernel/linux/linux-6.1.83/rootfs.cpio.lz4
ROOTFS_FULL_DEVICES_TABLE=$CURR_DIR/tools/full_devices_table.txt
ROOTFS_DIR=$CURR_DIR/rootfs
FAKEROOT_SCRIPT=$ROOTFS_DIR/fakeroot
TARGET_DIR=$ROOTFS_DIR/target

# Function to detect Ubuntu version
os_version() {
    if [ -f /etc/os-release ]; then
        if grep -q "Ubuntu" /etc/os-release; then
            VERSION_ID=$(grep "VERSION_ID" /etc/os-release | cut -d\" -f2)
            echo "$VERSION_ID"
            return 0
        fi
    fi
    return 1
}

# Function to copy files
cp_file() {
    src=$1
    dest=$2
    if [ -d "$src" ]; then
        cp -r "$src" "$dest"
    elif [ -f "$src" ]; then
        cp "$src" "$dest"
    else
        echo "Warning: Source '$src' does not exist."
    fi
}

# Function to create rootfs structure
mk_rootfs() {
    mkdir -p "$ROOTFS_DIR"
    mkdir -p "$TARGET_DIR"

    cp_file "$ROOTFS_CPIO_LZ4" "$ROOTFS_DIR"
    lz4 -d "$ROOTFS_DIR/rootfs.cpio.lz4" "$ROOTFS_DIR/rootfs.cpio"
    cpio -i -F "$ROOTFS_DIR/rootfs.cpio" -D "$TARGET_DIR"

    cp_file "$WORKSPACE/msp/out/bin" "$TARGET_DIR/usr/"
    cp_file "$WORKSPACE/msp/out/lib" "$TARGET_DIR/usr/"
    cp_file "$WORKSPACE/msp/out/etc" "$TARGET_DIR/"

    mkdir -p "$TARGET_DIR/opt/ko"
    find "$WORKSPACE/build/out/$PLATFORM/objs/kernel/linux/linux-6.1.83/" -name "*.ko" | xargs -I {} cp {} "$TARGET_DIR/opt/ko/"
    find "$WORKSPACE/build/out/$PLATFORM/objs/kernel/osdrv/out/ko/" -name "*.ko" | xargs -I {} cp {} "$TARGET_DIR/opt/ko/"
}

# Function to generate fakeroot script
mk_fakeroot_script() {
    echo '#!/usr/bin/env bash' > "$FAKEROOT_SCRIPT"
    echo "set -e" >> "$FAKEROOT_SCRIPT"

    echo "chown -h -R 0:0 $TARGET_DIR" >> "$FAKEROOT_SCRIPT"
    echo "chown -h -R 100:101 $TARGET_DIR/var/empty" >> "$FAKEROOT_SCRIPT"
    echo "$CURR_DIR/tools/bin/makedevs -d $ROOTFS_FULL_DEVICES_TABLE $TARGET_DIR" >> "$FAKEROOT_SCRIPT"
    echo "mkdir -p $TARGET_DIR/dev" >> "$FAKEROOT_SCRIPT"
    echo "mknod -m 0622 $TARGET_DIR/dev/console c 5 1" >> "$FAKEROOT_SCRIPT"

    echo "find $TARGET_DIR/run/ -mindepth 1 -prune -print0 | xargs -0r rm -rf --" >> "$FAKEROOT_SCRIPT"
    echo "find $TARGET_DIR/tmp/ -mindepth 1 -prune -print0 | xargs -0r rm -rf --" >> "$FAKEROOT_SCRIPT"

    echo "cd $TARGET_DIR && find . | LC_ALL=C sort | cpio --quiet -o -H newc -F $ROOTFS_DIR/rootfs_full.cpio" >> "$FAKEROOT_SCRIPT"

    chmod a+x "$FAKEROOT_SCRIPT"
}

# Function to rebuild kernel and copy images
build_kernel() {
    lz4 -l -9 "$ROOTFS_DIR/rootfs_full.cpio" "$ROOTFS_DIR/rootfs_full.cpio.lz4"

    cp_file "$ROOTFS_DIR/rootfs_full.cpio.lz4" "$ROOTFS_CPIO_LZ4"

    cd "$WORKSPACE/kernel/linux"
    make PLAT="$PLATFORM" linux-rebuild

    local IMG_DIR="$WORKSPACE/build/out/$PLATFORM/images/"
    local KERNEL_DIR="$WORKSPACE/build/out/$PLATFORM/objs/kernel/linux/linux-6.1.83/arch/arm64/boot/"

    cp_file "$ROOTFS_DIR/rootfs_full.cpio.lz4" "$IMG_DIR"
    cp_file "$KERNEL_DIR/Image" "$IMG_DIR/Image_full"
    cp_file "$KERNEL_DIR/Image.gz" "$IMG_DIR/Image_full.gz"
}

# Main script execution
if [ ! -e "$ROOTFS_CPIO_LZ4" ]
then
    exit 0
fi

set -x

# Use system fakeroot if available, otherwise use the local one
if which fakeroot >/dev/null 2>&1; then
    FAKEROOT=$(which fakeroot)
else
    # Check Ubuntu version before using local fakeroot
    if os_version; then
        UBUNTU_VERSION=$(os_version)
        if [ "$UBUNTU_VERSION" != "20.04" ]; then
            echo "ERROR: Local fakeroot was compiled on Ubuntu 20.04 and is only compatible with Ubuntu 20.04."
            exit 1
        fi
    fi
    export FAKEROOT_PREFIX=$CURR_DIR/tools
    FAKEROOT=$CURR_DIR/tools/bin/fakeroot
fi

mk_rootfs
mk_fakeroot_script

FAKEROOTDONTTRYCHOWN=1 $FAKEROOT -- "$FAKEROOT_SCRIPT"

build_kernel

rm -rf "$ROOTFS_DIR"