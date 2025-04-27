#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#
# Extracts a rootfs archive (cpio/gz/lz4), adds project-specific files,
# creates device nodes via fakeroot, and repackages it.
#

ROOTFS_ARCHIVE=""
PLATFORM=""
DO_PACKAGING=true
DEBUG_MODE=false
CUSTOM_TARGET_DIR=""

usage() {
    echo "Usage: $0 [-hdN] -r <rootfs_archive> [-p <platform>] [-T <target_dir>]"
    echo "  -h: Show help message"
    echo "  -d: Enable debug mode (set -x)"
    echo "  -r <rootfs_archive>: Specify the path to the input rootfs archive (e.g., rootfs.cpio, rootfs.cpio.gz, rootfs.cpio.lz4)"
    echo "  -p <platform>: Specify the platform (optional, used for default output paths)"
    echo "  -T <target_dir>: Specify the target directory path (optional, defaults to <rootfs_dir>/target)"
    echo "  -N: No packaging. Only extract, copy files, and run fakeroot script up to device node creation. Skip final CPIO creation and compression."
    exit 1
}

while getopts "hdr:p:T:N" opt; do
    case $opt in
        r)
            ROOTFS_ARCHIVE="$OPTARG"
            ;;
        p)
            PLATFORM="$OPTARG"
            ;;
        T)
            CUSTOM_TARGET_DIR="$OPTARG"
            ;;
        N)
            DO_PACKAGING=false
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
if [ -z "$ROOTFS_ARCHIVE" ]; then
    echo "ROOTFS_ARCHIVE must be specified."
    usage
fi

# Validate input rootfs archive existence
if [ ! -f "$ROOTFS_ARCHIVE" ]; then
    echo "Error: Input rootfs archive '$ROOTFS_ARCHIVE' not found."
    exit 1
fi

# Determine output suffix based on input archive
INPUT_BASENAME=$(basename "$ROOTFS_ARCHIVE")
OUTPUT_SUFFIX=""
case "$INPUT_BASENAME" in
    *.cpio.lz4)
        OUTPUT_SUFFIX=".lz4"
        ;;
    *.cpio.gz)
        OUTPUT_SUFFIX=".gz"
        ;;
    *.cpio)
        OUTPUT_SUFFIX=""
        ;;
    *)
        echo "Error: Unsupported rootfs archive format in filename '$INPUT_BASENAME'. Use .cpio, .cpio.gz, or .cpio.lz4"
        exit 1
        ;;
esac

if [ -z "$PLATFORM" ]; then
    echo "Error: Platform must be specified using -p."
    usage
fi

# Determine BUILD_DIR based on script location relative to build directory
# Assuming this script is in build/scripts/
BUILD_DIR=$(cd "$(dirname "$0")/.." ; pwd)
WORKSPACE=$(cd "$BUILD_DIR/.." ; pwd)

ROOTFS_FULL_DEVICES_TABLE=$BUILD_DIR/tools/full_devices_table.txt
ROOTFS_DIR=$BUILD_DIR/out/$PLATFORM/objs/rootfs
FAKEROOT_SCRIPT=$ROOTFS_DIR/fakeroot

if [ -n "$CUSTOM_TARGET_DIR" ]; then
    TARGET_DIR="$CUSTOM_TARGET_DIR"
    echo "Using custom target directory: $TARGET_DIR"
else
    TARGET_DIR="$ROOTFS_DIR/target"
    echo "Using default target directory: $TARGET_DIR"
fi

FINAL_OUTPUT_DIR="$WORKSPACE/build/out/$PLATFORM/images"
FINAL_OUTPUT_BASE_NAME="rootfs_full.cpio"
FINAL_OUTPUT_FILE="$ROOTFS_DIR/${FINAL_OUTPUT_BASE_NAME}${OUTPUT_SUFFIX}"
FINAL_OUTPUT_DEST="$FINAL_OUTPUT_DIR/${FINAL_OUTPUT_BASE_NAME}${OUTPUT_SUFFIX}"

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

cp_file() {
    src=$1
    dest_dir=$2
    dest_path="$dest_dir/$(basename "$src")"

    mkdir -p "$(dirname "$dest_path")"

    if [ -d "$src" ]; then
        cp -rL "$src" "$dest_dir/"
    elif [ -f "$src" ]; then
        cp -L "$src" "$dest_path"
    else
        echo "Warning: Source '$src' does not exist or is not a regular file/directory."
    fi
}

copy_additional_files() {
    echo "Copying additional files ..."

    mkdir -p "$TARGET_DIR/opt/msp"
    cp_file "$WORKSPACE/msp/out/bin" "$TARGET_DIR/opt/msp/"
    cp_file "$WORKSPACE/msp/out/lib" "$TARGET_DIR/opt/msp/"
    cp_file "$WORKSPACE/msp/out/etc" "$TARGET_DIR/opt/msp/"

    mkdir -p "$TARGET_DIR/lib/optee_armtz"
    cp_file "$WORKSPACE/msp/out/ta" "$TARGET_DIR/lib/optee_armtz/"

    mkdir -p "$TARGET_DIR/opt/ko"
    # Use find with -exec cp {} "$TARGET_DIR/opt/ko/" \; for potentially better handling of many files
    local linux_ko_dir="$WORKSPACE/build/out/$PLATFORM/objs/kernel/linux/linux-6.1.83/"
    if [ -d "$linux_ko_dir" ]; then
        find "$linux_ko_dir" -name "*.ko" -exec cp {} "$TARGET_DIR/opt/ko/" \; 2>/dev/null
    else
        echo "Warning: '$linux_ko_dir' not found. Skipping copy."
    fi

    local osdrv_ko_dir="$WORKSPACE/build/out/$PLATFORM/objs/kernel/osdrv/out/ko/"
    if [ -d "$osdrv_ko_dir" ]; then
        find "$osdrv_ko_dir" -name "*.ko" -exec cp {} "$TARGET_DIR/opt/ko/" \; 2>/dev/null
    else
        echo "Warning: '$osdrv_ko_dir' not found. Skipping copy."
    fi

    local initd_dir="$WORKSPACE/build/scripts/init_scripts/initd/"
    if [ -d "$initd_dir" ]; then
        find "$initd_dir" -name "S*" -exec cp {} "$TARGET_DIR/etc/init.d/" \; 2>/dev/null
    else
        echo "Warning: '$initd_dir' not found. Skipping copy."
    fi

    local init_scripts_dir="$WORKSPACE/build/scripts/init_scripts/"
    if [ -d "$init_scripts_dir" ]; then
        find "$init_scripts_dir" -maxdepth 1 -name "*.sh" -exec cp {} "$TARGET_DIR/usr/bin/" \; 2>/dev/null
    else
        echo "Warning: '$init_scripts_dir' not found. Skipping copy."
    fi

    # --- Add other file/directory copies below this line ---
    # Example: cp_file "$WORKSPACE/some/other/component" "$TARGET_DIR/usr/local/bin/"
}

mk_rootfs() {
    rm -rf "$TARGET_DIR"
    mkdir -p "$ROOTFS_DIR"
    mkdir -p "$TARGET_DIR"

    local temp_cpio="$ROOTFS_DIR/rootfs.cpio"
    echo "Processing input rootfs archive: $ROOTFS_ARCHIVE"

    case "$ROOTFS_ARCHIVE" in
        *.cpio.lz4)
            echo "Decompressing lz4 archive..."
            lz4 -d "$ROOTFS_ARCHIVE" "$temp_cpio" || { echo "lz4 decompression failed"; exit 1; }
            ;;
        *.cpio.gz)
            echo "Decompressing gzip archive..."
            gunzip -c "$ROOTFS_ARCHIVE" > "$temp_cpio" || { echo "gunzip decompression failed"; exit 1; }
            ;;
        *.cpio)
            echo "Copying cpio archive..."
            cp "$ROOTFS_ARCHIVE" "$temp_cpio" || { echo "cpio copy failed"; exit 1; }
            ;;
        *)
            # This case should technically not be reached due to earlier check, but added for safety
            echo "Error: Unsupported rootfs archive format. Use .cpio, .cpio.gz, or .cpio.lz4"
            exit 1
            ;;
    esac

    echo "Extracting rootfs cpio archive..."
    # Temporarily disable exit on error for cpio extraction
    set +e
    (cd "$TARGET_DIR" && cpio -i --no-preserve-owner -F "$temp_cpio")
    local cpio_exit_status=$? # Capture the exit status for potential logging/debugging
    # Re-enable exit on error
    set -e

    # Log if cpio had issues, but don't exit
    if [ $cpio_exit_status -ne 0 ]; then
        echo "Warning: cpio extraction finished with status $cpio_exit_status. Continuing..."
    fi

    echo "Cleaning up temporary cpio file..."
    rm "$temp_cpio"

    copy_additional_files
}

mk_fakeroot_script() {
    echo "Generating fakeroot script ..."
    echo '#!/usr/bin/env bash' > "$FAKEROOT_SCRIPT"
    echo "set -e" >> "$FAKEROOT_SCRIPT"
    echo "echo 'Running fakeroot script commands ...'" >> "$FAKEROOT_SCRIPT"

    echo "echo 'Changing ownership...'" >> "$FAKEROOT_SCRIPT"
    echo "chown -h -R 0:0 $TARGET_DIR" >> "$FAKEROOT_SCRIPT"
    # echo "chown -h -R 100:101 $TARGET_DIR/var/empty" >> "$FAKEROOT_SCRIPT"

    echo "echo 'Creating device nodes ...'" >> "$FAKEROOT_SCRIPT"
    if [ -f "$ROOTFS_FULL_DEVICES_TABLE" ]; then
        echo "$BUILD_DIR/tools/bin/makedevs -d $ROOTFS_FULL_DEVICES_TABLE $TARGET_DIR" >> "$FAKEROOT_SCRIPT"
    else
        echo "echo 'Warning: $ROOTFS_FULL_DEVICES_TABLE not found, skipping makedevs.'" >> "$FAKEROOT_SCRIPT"
    fi
    echo "mkdir -p $TARGET_DIR/dev" >> "$FAKEROOT_SCRIPT"
    echo "mknod -m 0622 $TARGET_DIR/dev/console c 5 1" >> "$FAKEROOT_SCRIPT"

    echo "echo 'Cleaning temporary directories ...'" >> "$FAKEROOT_SCRIPT"
    echo "find $TARGET_DIR/run/ -mindepth 1 -prune -print0 2>/dev/null | xargs -0r rm -rf --" >> "$FAKEROOT_SCRIPT"
    echo "find $TARGET_DIR/tmp/ -mindepth 1 -prune -print0 2>/dev/null | xargs -0r rm -rf --" >> "$FAKEROOT_SCRIPT"

    if [ "$DO_PACKAGING" = true ]; then
        echo "echo 'Creating final cpio archive ...'" >> "$FAKEROOT_SCRIPT"
        echo "cd $TARGET_DIR && find . | LC_ALL=C sort | cpio --quiet -o -H newc -F $ROOTFS_DIR/$FINAL_OUTPUT_BASE_NAME" >> "$FAKEROOT_SCRIPT"
    else
         echo "echo 'Skipping final CPIO archive creation as requested.'" >> "$FAKEROOT_SCRIPT"
    fi

    echo "echo 'Fakeroot script finished.'" >> "$FAKEROOT_SCRIPT"

    chmod a+x "$FAKEROOT_SCRIPT"
}

# Main script execution
set -e # Exit on error

if [ "$DEBUG_MODE" = true ]; then
    echo "Debug mode enabled."
    set -x
fi

echo "Starting rootfs packaging process ..."

# Use system fakeroot if available, otherwise use the local one
if which fakeroot >/dev/null 2>&1; then
    FAKEROOT_CMD=$(which fakeroot)
    echo "Using system fakeroot: $FAKEROOT_CMD"
else
    # Check Ubuntu version before using local fakeroot
    if os_version; then
        UBUNTU_VERSION=$(os_version)
        if [ "$UBUNTU_VERSION" != "20.04" ]; then
            echo "ERROR: Local fakeroot was compiled on Ubuntu 20.04 and might only be compatible with Ubuntu 20.04."
            echo "Attempting to use it anyway..."
            exit 1 # Optionally exit if strict compatibility is needed
        fi
    fi
    export FAKEROOT_PREFIX=$BUILD_DIR/tools
    FAKEROOT_CMD=$BUILD_DIR/tools/bin/fakeroot
    if [ ! -x "$FAKEROOT_CMD" ]; then
        echo "Error: Local fakeroot not found or not executable at $FAKEROOT_CMD"
        exit 1
    fi
    echo "Using local fakeroot: $FAKEROOT_CMD"
fi

mk_rootfs
mk_fakeroot_script

echo "Executing fakeroot script: $FAKEROOT_SCRIPT ..."
FAKEROOTDONTTRYCHOWN=1 $FAKEROOT_CMD -- "$FAKEROOT_SCRIPT" || { echo "Fakeroot execution failed"; exit 1; }

if [ "$DO_PACKAGING" = true ]; then
    INTERMEDIATE_CPIO="$ROOTFS_DIR/$FINAL_OUTPUT_BASE_NAME"
    if [ ! -f "$INTERMEDIATE_CPIO" ]; then
        echo "Error: Intermediate CPIO file '$INTERMEDIATE_CPIO' was not created by fakeroot script."
        exit 1
    fi
    echo "Processing final rootfs archive (Format: ${OUTPUT_SUFFIX:-.cpio}) ..."
    case "$OUTPUT_SUFFIX" in
        .lz4)
            echo "Compressing final rootfs archive with lz4 ..."
            lz4 -l -9 "$INTERMEDIATE_CPIO" "$FINAL_OUTPUT_FILE" || { echo "lz4 compression failed"; exit 1; }
            rm "$INTERMEDIATE_CPIO"
            ;;
        .gz)
            echo "Compressing final rootfs archive with gzip ..."
            gzip -c9 "$INTERMEDIATE_CPIO" > "$FINAL_OUTPUT_FILE" || { echo "gzip compression failed"; exit 1; }
            rm "$INTERMEDIATE_CPIO"
            ;;
        *)
            echo "Using uncompressed cpio archive ..."
            mv "$INTERMEDIATE_CPIO" "$FINAL_OUTPUT_FILE" || { echo "Failed to move final cpio file"; exit 1; }
            ;;
    esac

    echo "Copying final archive to output directory ..."
    mkdir -p "$FINAL_OUTPUT_DIR"
    cp_file "$FINAL_OUTPUT_FILE" "$FINAL_OUTPUT_DIR" || { echo "Failed to copy final archive"; exit 1; }

    echo "Cleaning up temporary directory ..."
    rm -rf "$ROOTFS_DIR"

    echo "-----------------------------------------------------"
    echo "Complete the packaging of rootfs."
    echo "Final rootfs archive: $FINAL_OUTPUT_DEST"
    echo "-----------------------------------------------------"
else
    echo "-----------------------------------------------------"
    echo "Complete the processing of rootfs (packaging skipped)."
    echo "Targeted rootfs directory: $TARGET_DIR"
    echo "Temporary rootfs directory: $ROOTFS_DIR"
    echo "-----------------------------------------------------"
fi

exit 0
