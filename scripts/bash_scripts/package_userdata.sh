#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#
# Only used to copy additional files to userdata directory
#

set -e

PLATFORM=""
CUSTOM_TARGET_DIR=""
FUSA_ENABLE=false
CROSS_ASANLIB_PATH=""

usage() {
    echo "Usage: $0 -p <platform> -T <target_dir> [-f] [-a <asanlib_path>]"
    echo "  -p <platform>: Specify platform"
    echo "  -T <target_dir>: Specify target directory"
    exit 1
}

while getopts "p:T:fa:" opt; do
    case $opt in
        p)
            PLATFORM="$OPTARG"
            ;;
        T)
            CUSTOM_TARGET_DIR="$OPTARG"
            ;;
        f)
            FUSA_ENABLE=true
            ;;
        a)
            CROSS_ASANLIB_PATH="$OPTARG"
            ;;
        *)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

if [ -z "$PLATFORM" ] || [ -z "$CUSTOM_TARGET_DIR" ]; then
    usage
fi

BUILD_DIR=$(cd "$(dirname "$0")/.." ; pwd)
WORKSPACE=$(cd "$BUILD_DIR/.." ; pwd)

TARGET_DIR="$CUSTOM_TARGET_DIR"

cp_file() {
    src=$1
    dest_dir=$2
    dest_path="$dest_dir/$(basename "$src")"

    mkdir -p "$(dirname "$dest_path")"

    if [ -d "$src" ]; then
        echo cp -rL "$src" "$dest_dir/"
        cp -rL "$src" "$dest_dir/"
    elif [ -f "$src" ]; then
        echo cp -L "$src" "$dest_path"
        cp -L "$src" "$dest_path"
    else
        echo "Warning: Source '$src' does not exist or is not a regular file/directory."
    fi
}

copy_additional_files() {
    echo "Copying additional files ..."
}

copy_additional_files

echo "userdata file copy finished, target directory: $TARGET_DIR"
