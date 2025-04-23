#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#
# Creates a root filesystem image (ubifs, ext4, or ubi) from an archive based on specified parameters.
#

# Exit on error
set -e
DEBUG_MODE=false

usage() {
    echo "Usage: $0 -r <rootfs_archive> -p <platform> -t <fs_type> -s <partition_size> -o <output_dir> [-y <yaml_config>] [-u <mkfs.ubifs_path>] [-m <mke2fs_path>] [-b <ubinize_path>] [-d]"
    echo "  -r <rootfs_archive>: Path to the input rootfs archive (e.g., rootfs.cpio.gz)"
    echo "  -p <platform>: Specify the platform"
    echo "  -t <fs_type>: Filesystem type to create ('ubifs', 'ext4', or 'ubi')"
    echo "  -s <partition_size>: Size of the rootfs partition (e.g., 100M, 256K, 1G, 471859200, 0x1C200000)"
    echo "  -y <yaml_config>: Path to the YAML config file (required for ubifs and ubi)"
    echo "  -o <output_dir>: Directory to store the final image"
    echo "  -u <mkfs.ubifs_path>: Path to the mkfs.ubifs executable directory (optional)"
    echo "  -m <mke2fs_path>: Path to the mke2fs executable directory (optional)"
    echo "  -b <ubinize_path>: Path to the ubinize executable directory (optional, for ubi type)"
    echo "  -d: Enable debug mode (set -x)"
    echo "  -h: Show help message"
    exit 1
}

parse_args() {
    local missing_arg_error=false
    while getopts "hr:p:t:s:y:o:u:m:b:d" opt; do
        case $opt in
            r) ROOTFS_ARCHIVE="$OPTARG" ;;
            p) PLATFORM="$OPTARG" ;;
            t) FS_TYPE="$OPTARG" ;;
            s) PARTITION_SIZE_STR="$OPTARG" ;;
            y) YAML_CONFIG="$OPTARG" ;;
            o) OUTPUT_DIR="$OPTARG" ;;
            u) MKFS_UBIFS_PATH="$OPTARG" ;;
            m) MKE2FS_PATH="$OPTARG" ;;
            b) UBINIZE_PATH="$OPTARG" ;;
            d) DEBUG_MODE=true ;;
            h) usage ;;
            \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
        esac
    done

    # Check required arguments individually
    if [ -z "$ROOTFS_ARCHIVE" ]; then
        echo "Error: Missing required argument: -r <rootfs_archive>" >&2
        missing_arg_error=true
    fi
    if [ -z "$PLATFORM" ]; then
        echo "Error: Missing required argument: -p <platform>" >&2
        missing_arg_error=true
    fi
    if [ -z "$FS_TYPE" ]; then
        echo "Error: Missing required argument: -t <fs_type>" >&2
        missing_arg_error=true
    fi
    if [ -z "$PARTITION_SIZE_STR" ]; then
        echo "Error: Missing required argument: -s <partition_size>" >&2
        missing_arg_error=true
    fi
    if [ -z "$OUTPUT_DIR" ]; then
        echo "Error: Missing required argument: -o <output_dir>" >&2
        missing_arg_error=true
    fi

    if [[ "$FS_TYPE" == "ubifs" || "$FS_TYPE" == "ubi" ]] && [ -z "$YAML_CONFIG" ]; then
        echo "Error: YAML config file (-y) is required when filesystem type (-t) is 'ubifs' or 'ubi'." >&2
        missing_arg_error=true
    fi

    # Check if filesystem type is valid only if it's provided
    if [ -n "$FS_TYPE" ] && [ "$FS_TYPE" != "ubifs" ] && [ "$FS_TYPE" != "ext4" ] && [ "$FS_TYPE" != "ubi" ]; then
        echo "Error: Invalid filesystem type '$FS_TYPE'. Must be 'ubifs', 'ext4', or 'ubi'." >&2
        missing_arg_error=true
    fi

    # If any required argument is missing, show usage and exit
    if [ "$missing_arg_error" = true ]; then
        usage
    fi

    if [ "$DEBUG_MODE" = true ]; then
        echo "Debug mode enabled."
        set -x
    fi
}

prepare_environment() {
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
    BUILD_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
    WORKSPACE=$(cd "$BUILD_DIR/.." && pwd)

    PACKAGE_ROOTFS_SCRIPT="$SCRIPT_DIR/package_rootfs.sh"
    PARSE_FLASH_YAML_SCRIPT="$SCRIPT_DIR/parse_flash_yaml.py"
    CREATE_UBIFS_SCRIPT="$SCRIPT_DIR/create_ubifs.py"
    CREATE_EXT4_SCRIPT="$SCRIPT_DIR/create_ext4.py"
    GENERATE_UBINIZE_CFG_SCRIPT="$SCRIPT_DIR/generate_ubinize_cfg.py"
    CREATE_UBI_SCRIPT="$SCRIPT_DIR/create_ubi.py"

    # Check if helper scripts exist
    for script in "$PACKAGE_ROOTFS_SCRIPT" "$PARSE_FLASH_YAML_SCRIPT" "$CREATE_UBIFS_SCRIPT" "$CREATE_EXT4_SCRIPT"; do
        if [ ! -f "$script" ]; then
            echo "Error: Helper script not found: $script"
            exit 1
        fi
    done
    # Check UBI specific scripts only if needed later? Or check all upfront. Checking all upfront.
    if [[ "$FS_TYPE" == "ubi" ]]; then
         for script in "$GENERATE_UBINIZE_CFG_SCRIPT" "$CREATE_UBI_SCRIPT"; do
            if [ ! -f "$script" ]; then
                echo "Error: Helper script not found for UBI creation: $script"
                exit 1
            fi
        done
    fi

    PREPARED_ROOTFS_DIR="$BUILD_DIR/out/$PLATFORM/objs/rootfs/$FS_TYPE"

    rm -rf "$PREPARED_ROOTFS_DIR"
    mkdir -p "$(dirname "$PREPARED_ROOTFS_DIR")"
    mkdir -p "$OUTPUT_DIR"
}

unfold_rootfs() {
    echo "Unfolding rootfs ..."

    local package_cmd_args=("$PACKAGE_ROOTFS_SCRIPT" -N -r "$ROOTFS_ARCHIVE" -p "$PLATFORM" -T "$PREPARED_ROOTFS_DIR")
    if [ "$DEBUG_MODE" = true ]; then
        package_cmd_args+=("-d")
    fi
    bash "${package_cmd_args[@]}"

    if [ ! -d "$PREPARED_ROOTFS_DIR" ]; then
        echo "Error: Unfolded rootfs directory not found: $PREPARED_ROOTFS_DIR"
        exit 1
    fi
    echo "Unfolded rootfs directory: $PREPARED_ROOTFS_DIR"
}

parse_partition_size() {
    echo "Parsing partition size '$PARTITION_SIZE_STR' ..."
    local size_val unit

    if [[ "$PARTITION_SIZE_STR" =~ ^0x[0-9a-fA-F]+$ ]]; then
        PARTITION_SIZE_BYTES=$((PARTITION_SIZE_STR))
    elif [[ "$PARTITION_SIZE_STR" =~ ^[0-9]+$ ]]; then
        PARTITION_SIZE_BYTES=$PARTITION_SIZE_STR
    else
        size_val=$(echo "$PARTITION_SIZE_STR" | sed 's/[KMG]$//i')
        unit=$(echo "$PARTITION_SIZE_STR" | grep -o '[KMG]$' || echo "")

        if ! [[ "$size_val" =~ ^[0-9]+$ ]] || [ "$size_val" -le 0 ]; then
            echo "Error: Invalid numeric part in partition size: '$PARTITION_SIZE_STR'."
            exit 1
        fi

        case "$unit" in
            k|K) PARTITION_SIZE_BYTES=$((size_val * 1024)) ;;
            m|M) PARTITION_SIZE_BYTES=$((size_val * 1024 * 1024)) ;;
            g|G) PARTITION_SIZE_BYTES=$((size_val * 1024 * 1024 * 1024)) ;;
            *) echo "Error: Invalid size unit in '$PARTITION_SIZE_STR'. Use K, M, G, decimal bytes, or hex bytes (0x...)."
               exit 1
               ;;
        esac
    fi

    if [ "$PARTITION_SIZE_BYTES" -le 0 ]; then
         echo "Error: Parsed partition size ($PARTITION_SIZE_BYTES bytes) must be positive."
         exit 1
    fi
    echo "Partition size: $PARTITION_SIZE_BYTES bytes"
}

parse_flash_yaml() {
    echo "Parsing flash parameters from $YAML_CONFIG ..."
    local flash_info page_hex block_hex

    flash_info=$(python3 "$PARSE_FLASH_YAML_SCRIPT" -f "$YAML_CONFIG")
    if [ $? -ne 0 ] || [ -z "$flash_info" ]; then
        echo "Error: Failed to parse YAML config file or received empty output: $YAML_CONFIG"
        exit 1
    fi

    FLASH_TYPE=$(echo "$flash_info" | grep "Flash Type:" | awk '{print $NF}')
    page_hex=$(echo "$flash_info" | grep "Page Size:" | awk '{print $NF}')
    block_hex=$(echo "$flash_info" | grep "Eraseblock Size:" | awk '{print $NF}')
    # Optional parameters
    # sub_page_hex=$(echo "$flash_info" | grep "Sub Page Size:" | awk '{print $NF}')
    # vid_hdr_offset_hex=$(echo "$flash_info" | grep "VID Header Offset:" | awk '{print $NF}')

    if [ -z "$FLASH_TYPE" ] || [ -z "$page_hex" ] || [ -z "$block_hex" ]; then
        echo "Error: Could not parse essential flash parameters (Type, Page Size, Eraseblock Size)."
        echo "Parsed $FLASH_TYPE flash information is:"
        echo "$flash_info"
        exit 1
    fi

    # Convert hex values (like 0x...) to decimal for calculations
    PAGE_SIZE_DEC=$((page_hex))
    BLOCK_SIZE_DEC=$((block_hex))
    # if [ -n "$sub_page_hex" ]; then SUB_PAGE_SIZE_DEC=$((sub_page_hex)); fi
    # if [ -n "$vid_hdr_offset_hex" ]; then VID_HDR_OFFSET=$((vid_hdr_offset_hex)); fi

    echo "Flash Params: Type=$FLASH_TYPE, Page=$PAGE_SIZE_DEC (0x${page_hex#0x}), Block=$BLOCK_SIZE_DEC (0x${block_hex#0x})"
}

create_ubifs_image() {
    echo "Creating ubifs: $FINAL_IMAGE_PATH ..."

    if [ -z "$FLASH_TYPE" ]; then
        parse_flash_yaml
    fi

    local flash_type leb_size overhead_lebs max_lebs cmd_args

    flash_type=$(echo "$FLASH_TYPE" | tr '[:upper:]' '[:lower:]')
    if [ "$flash_type" = "nand" ]; then
        leb_size=$((BLOCK_SIZE_DEC - 2 * PAGE_SIZE_DEC))
        echo "LEB size (NAND): $BLOCK_SIZE_DEC - 2 * $PAGE_SIZE_DEC = $leb_size"
    elif [ "$flash_type" = "nor" ]; then
        leb_size=$((BLOCK_SIZE_DEC - 1 * PAGE_SIZE_DEC))
        echo "LEB size (NOR): $BLOCK_SIZE_DEC - 1 * $PAGE_SIZE_DEC = $leb_size"
    else
        echo "Error: Unknown flash type '$FLASH_TYPE'."
        exit 1
    fi

    if [ $leb_size -le 0 ]; then
        echo "Error: Calculated LEB size ($leb_size) is not positive."
        exit 1
    fi
    echo "Calculated LEB Size: $leb_size"

    # Calculate max LEB count
    # Formula: max_leb_cnt = floor(partition_size / leb_size)
    # Subtract a few LEBs for UBIFS overhead (e.g., 4 for journal, VID header, EC header etc.)
    overhead_lebs=4
    max_lebs=$((PARTITION_SIZE_BYTES / leb_size - overhead_lebs))
    if [ $max_lebs -le 0 ]; then
        echo "Error: Max LEB count ($max_lebs) too small. Check partition/LEB size."
        exit 1
    fi
    echo "Max LEB Count: $max_lebs (Partition: $PARTITION_SIZE_BYTES / LEB: $leb_size - Overhead: $overhead_lebs)"

    cmd_args=(python3 "$CREATE_UBIFS_SCRIPT"
                    -o "$FINAL_IMAGE_PATH"
                    -d "$PREPARED_ROOTFS_DIR"
                    -m "$PAGE_SIZE_DEC"
                    -e "$leb_size"
                    -c "$max_lebs")
    if [ -n "$MKFS_UBIFS_PATH" ]; then
        cmd_args+=("-u" "$MKFS_UBIFS_PATH")
    fi

    "${cmd_args[@]}"
}

create_ubi_image() {
    echo "Creating ubi image ..."
    local cfg_path="$OUTPUT_DIR/ubinize.cfg"
    local ubi_args

    FINAL_IMAGE_PATH="$OUTPUT_DIR/rootfs.ubifs"
    create_ubifs_image

    if [ ! -f "$FINAL_IMAGE_PATH" ]; then
        echo "Error: Failed to create ubifs: $FINAL_IMAGE_PATH"
        exit 1
    fi
    echo "ubifs created: $FINAL_IMAGE_PATH"

    echo "Generating ubinize.cfg: $cfg_path ..."
    python3 "$GENERATE_UBINIZE_CFG_SCRIPT" \
        -o "$cfg_path" \
        -i "$FINAL_IMAGE_PATH" \
        -s "$PARTITION_SIZE_BYTES"
    if [ ! -f "$cfg_path" ]; then
        echo "Error: Failed to generate ubinize config: $cfg_path"
        rm -f "$FINAL_IMAGE_PATH"
        exit 1
    fi
    if [ "$DEBUG_MODE" = true ]; then
        echo "----- ubinize.cfg content -----"
        cat "$cfg_path"
        echo "-------------------------------"
    fi

    if [ -z "$FLASH_TYPE" ]; then
        echo "Error: Flash parameters missing for create_ubi.py"
        rm -f "$FINAL_IMAGE_PATH" "$cfg_path"
        exit 1
    fi

    FINAL_IMAGE_PATH="$OUTPUT_DIR/rootfs.$FS_TYPE"
    echo "Creating UBI image: $FINAL_IMAGE_PATH ..."

    ubi_args=(python3 "$CREATE_UBI_SCRIPT"
                  -o "$FINAL_IMAGE_PATH"
                  -c "$cfg_path"
                  -p "$BLOCK_SIZE_DEC"
                  -m "$PAGE_SIZE_DEC")

    if [ -n "$UBINIZE_PATH" ]; then
        ubi_args+=("-b" "$UBINIZE_PATH")
    fi

    "${ubi_args[@]}"
}

create_ext4_image() {
    echo "Creating ext4 image ..."
    echo "Using size string: $PARTITION_SIZE_STR"
    local ext4_args

    ext4_args=(python3 "$CREATE_EXT4_SCRIPT"
                   -o "$FINAL_IMAGE_PATH"
                   -d "$PREPARED_ROOTFS_DIR"
                   -s "$PARTITION_SIZE_STR"
                   -l "rootfs")
    if [ -n "$MKE2FS_PATH" ]; then
        ext4_args+=("-m" "$MKE2FS_PATH")
    fi

    "${ext4_args[@]}"
}

main() {
    parse_args "$@"
    prepare_environment

    echo "----- Starting rootfs.$FS_TYPE Image Creation -----"
    echo "Platform: $PLATFORM"
    echo "Input: $ROOTFS_ARCHIVE"
    echo "FS Type: $FS_TYPE"
    echo "Partition Size: $PARTITION_SIZE_STR"
    echo "Output Dir: $OUTPUT_DIR"
    if [[ "$FS_TYPE" == "ubifs" || "$FS_TYPE" == "ubi" ]]; then
        echo "YAML Config: $YAML_CONFIG"
    fi

    unfold_rootfs

    echo "Creating rootfs.$FS_TYPE image ..."
    FINAL_IMAGE_NAME="rootfs.$FS_TYPE"
    FINAL_IMAGE_PATH="$OUTPUT_DIR/$FINAL_IMAGE_NAME"

    if [[ "$FS_TYPE" == "ubifs" || "$FS_TYPE" == "ubi" ]]; then
        parse_partition_size
        parse_flash_yaml
    fi

    if [ "$FS_TYPE" = "ubifs" ]; then
        create_ubifs_image
    elif [ "$FS_TYPE" = "ubi" ]; then
        create_ubi_image
    elif [ "$FS_TYPE" = "ext4" ]; then
        create_ext4_image
    fi

    echo "----- Complete rootfs.$FS_TYPE Image Creation -----"
    echo "Final Image: $FINAL_IMAGE_PATH"
    echo "Prepared rootfs: $PREPARED_ROOTFS_DIR"
    echo "---------------------------------------------------"

    # Optional cleanup
    # rm -rf "$PREPARED_ROOTFS_DIR"

    exit 0
}

main "$@"
