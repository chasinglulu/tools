#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#
# Runs package_rootfs.sh, updates kernel rootfs, rebuilds kernel, copies images.
#

PLATFORM=""
DEBUG_MODE=false

usage() {
    echo "Usage: $0 [-hd] -p <platform>"
    echo "  -h: Show help message"
    echo "  -d: Enable debug mode (set -x)"
    echo "  -p <platform>: Specify the platform"
    exit 1
}

while getopts "hdp:" opt; do
    case $opt in
        p)
            PLATFORM="$OPTARG"
            ;;
        d)
            DEBUG_MODE=true
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

shift $((OPTIND-1))

# Check if required arguments are provided
if [ -z "$PLATFORM" ]; then
    echo "PLATFORM must be specified."
    usage
fi

# Determine BUILD_DIR based on script location relative to build directory
# Assuming this script is in build/scripts/
BUILD_DIR=$(cd "$(dirname "$0")/.." ; pwd)
WORKSPACE=$(cd "$BUILD_DIR/.." ; pwd)

INITIAL_ROOTFS_CPIO_LZ4=$WORKSPACE/build/out/$PLATFORM/objs/kernel/linux/linux-6.1.83/rootfs.cpio.lz4
PACKAGED_ROOTFS_PATH="$WORKSPACE/build/out/$PLATFORM/images/rootfs_full.cpio.lz4"
PACKAGE_SCRIPT="$BUILD_DIR/scripts/package_rootfs.sh"

build_kernel() {
    echo "Updating rootfs for kernel build..."
    # Copy the full rootfs created by package_rootfs.sh back to the location kernel build expects
    if [ -f "$PACKAGED_ROOTFS_PATH" ]; then
        mkdir -p "$(dirname "$INITIAL_ROOTFS_CPIO_LZ4")"
        cp "$PACKAGED_ROOTFS_PATH" "$INITIAL_ROOTFS_CPIO_LZ4" || { echo "Failed to copy packaged rootfs to kernel build location"; exit 1; }
    else
        echo "Error: Packaged rootfs '$PACKAGED_ROOTFS_PATH' not found after running package_rootfs.sh."
        exit 1
    fi

    # Check if kernel source directory exists
    if [ ! -d "$WORKSPACE/kernel/linux" ]; then
        echo "Warning: Kernel source directory '$WORKSPACE/kernel/linux' not found. Skipping kernel rebuild."
        return
    fi

    echo "Rebuilding kernel..."
    cd "$WORKSPACE/kernel/linux"
    make PLAT="$PLATFORM" linux-rebuild || { echo "Kernel rebuild failed"; exit 1; }

    local IMG_DIR="$WORKSPACE/build/out/$PLATFORM/images/"
    local KERNEL_DIR="$WORKSPACE/build/out/$PLATFORM/objs/kernel/linux/linux-6.1.83/arch/arm64/boot/"

    echo "Copying kernel images..."
    mkdir -p "$IMG_DIR"
    if [ -f "$KERNEL_DIR/Image" ]; then
        cp "$KERNEL_DIR/Image" "$IMG_DIR/Image_full"
    else
        echo "Warning: Kernel image '$KERNEL_DIR/Image' not found."
    fi
    if [ -f "$KERNEL_DIR/Image.gz" ]; then
        cp "$KERNEL_DIR/Image.gz" "$IMG_DIR/Image_full.gz"
    else
        echo "Warning: Kernel image '$KERNEL_DIR/Image.gz' not found."
    fi
}

# Main script execution
if [ ! -e "$INITIAL_ROOTFS_CPIO_LZ4" ]
then
    echo "Initial rootfs '$INITIAL_ROOTFS_CPIO_LZ4' not found. Exiting."
    exit 0
fi

if [ "$DEBUG_MODE" = true ]; then
    echo "Debug mode enabled."
    set -x
fi

set -e # Enable exit on error for the main part

echo "Running package_rootfs.sh to prepare full rootfs..."
package_args=("-r" "$INITIAL_ROOTFS_CPIO_LZ4" "-p" "$PLATFORM")
if [ "$DEBUG_MODE" = true ]; then
    package_args+=("-d")
fi

# Execute package_rootfs.sh
"$PACKAGE_SCRIPT" "${package_args[@]}" || { echo "package_rootfs.sh failed"; exit 1; }

echo "Building kernel and copying images..."
build_kernel

echo "Fixup process complete."
exit 0