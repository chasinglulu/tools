#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#
# Creates a userdata filesystem image (ubifs, ext4, ubi, or squashfs)
# from a directory based on specified parameters.
#

# Exit on error
set -e
DEBUG_MODE=false
CONVERT_TO_SPARSE=false

usage() {
    echo "Usage: $0 -t <fs_type> -s <partition_size> -o <output_dir> [-i <input_dir>] [-y <yaml_config>] [-u <mkfs.ubifs_path>] [-m <mke2fs_path>] [-b <ubinize_path>] [-q <mksquashfs_path>] [-g <img2simg_path>] [-d]"
    echo "  -i <input_dir>: Path to the input userdata directory (optional, creates empty fs if not provided)"
    echo "  -p <platform>: Specify the platform"
    echo "  -t <fs_type>: Filesystem type to create ('ubifs', 'ext4', 'ubi' or 'squash')"
    echo "  -s <partition_size>: Size of the userdata partition (e.g., 100M, 256K, 1G, 471859200, 0x1C200000)"
    echo "  -y <yaml_config>: Path to the YAML config file (required for ubifs and ubi)"
    echo "  -o <output_dir>: Directory to store the final image"
    echo "  -u <mkfs.ubifs_path>: Path to the mkfs.ubifs executable directory (optional)"
    echo "  -m <mke2fs_path>: Path to the mke2fs executable directory (optional)"
    echo "  -b <ubinize_path>: Path to the ubinize executable directory (optional, for ubi type)"
    echo "  -q <mksquashfs_path>: Path to the mksquashfs executable directory (optional, for squash type)"
    echo "  -g <img2simg_path>: Path to the img2simg executable directory (optional, for sparse image)"
    echo "  -Z: Convert the final image to a sparse image"
    echo "  -d: Enable debug mode (set -x)"
    echo "  -h: Show help message"
    exit 1
}

parse_args() {
    local missing_arg_error=false
    while getopts "hi:p:t:s:y:o:u:m:q:b:g:dZ" opt; do
        case $opt in
            i) INPUT_DIR="$OPTARG" ;;
            p) PLATFORM="$OPTARG" ;;
            t) FS_TYPE="$OPTARG" ;;
            s) PARTITION_SIZE_STR="$OPTARG" ;;
            y) YAML_CONFIG="$OPTARG" ;;
            o) OUTPUT_DIR="$OPTARG" ;;
            u) MKFS_UBIFS_PATH="$OPTARG" ;;
            m) MKE2FS_PATH="$OPTARG" ;;
            q) MKSQUASH_PATH="$OPTARG" ;;
            b) UBINIZE_PATH="$OPTARG" ;;
            g) IMG2SIMG_PATH="$OPTARG" ;;
            d) DEBUG_MODE=true ;;
            Z) CONVERT_TO_SPARSE=true ;;
            h) usage ;;
            \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
        esac
    done

    # Check required arguments individually
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
    if [ -n "$FS_TYPE" ] && [ "$FS_TYPE" != "ubifs" ] && [ "$FS_TYPE" != "ext4" ] && [ "$FS_TYPE" != "ubi" ] && [ "$FS_TYPE" != "squash" ]; then
        echo "Error: Invalid filesystem type '$FS_TYPE'. Must be 'ubifs', 'ext4', 'ubi' or 'squash'." >&2
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

    PARSE_FLASH_YAML_SCRIPT="$SCRIPT_DIR/parse_flash_yaml.py"
    CREATE_UBIFS_SCRIPT="$SCRIPT_DIR/create_ubifs.py"
    CREATE_EXT4_SCRIPT="$SCRIPT_DIR/create_ext4.py"
    GENERATE_UBINIZE_CFG_SCRIPT="$SCRIPT_DIR/generate_ubinize_cfg.py"
    CREATE_UBI_SCRIPT="$SCRIPT_DIR/create_ubi.py"
    CREATE_SQUASH_SCRIPT="$SCRIPT_DIR/create_squash.py"
    CREATE_SPARSE_SCRIPT="$SCRIPT_DIR/create_sparse.py"
    PACKAGE_USERDATA_SCRIPT="$SCRIPT_DIR/package_userdata.sh"

    # Check if helper scripts exist
    for script in "$PARSE_FLASH_YAML_SCRIPT" "$CREATE_UBIFS_SCRIPT" "$CREATE_EXT4_SCRIPT" "$CREATE_SQUASH_SCRIPT"; do
        if [ ! -f "$script" ]; then
            echo "Error: Helper script not found: $script"
            exit 1
        fi
    done
    # Check if package_userdata.sh exists
    if [ ! -f "$PACKAGE_USERDATA_SCRIPT" ]; then
        echo "Error: Helper script not found: $PACKAGE_USERDATA_SCRIPT"
        exit 1
    fi
    if [[ "$FS_TYPE" == "ubi" ]]; then
         for script in "$GENERATE_UBINIZE_CFG_SCRIPT" "$CREATE_UBI_SCRIPT"; do
            if [ ! -f "$script" ]; then
                echo "Error: UBI helper script not found: $script"
                exit 1
            fi
        done
    fi
    if [ "$CONVERT_TO_SPARSE" = true ]; then
        if [ ! -f "$CREATE_SPARSE_SCRIPT" ]; then
            echo "Error: Sparse image helper script not found: $CREATE_SPARSE_SCRIPT"
            exit 1
        fi
    fi

    PREPARED_USERDATA_DIR="$BUILD_DIR/out/$PLATFORM/objs/userdata/$FS_TYPE"

    rm -rf "$PREPARED_USERDATA_DIR"
    mkdir -p "$PREPARED_USERDATA_DIR"
    mkdir -p "$OUTPUT_DIR"
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

    if [ -z "$FLASH_TYPE" ] || [ -z "$page_hex" ] || [ -z "$block_hex" ]; then
        echo "Error: Could not parse essential flash parameters (Type, Page Size, Eraseblock Size)."
        echo "Parsed $FLASH_TYPE flash information is:"
        echo "$flash_info"
        exit 1
    fi

    PAGE_SIZE_DEC=$((page_hex))
    BLOCK_SIZE_DEC=$((block_hex))

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

    overhead_lebs=4
    max_lebs=$((PARTITION_SIZE_BYTES / leb_size - overhead_lebs))
    if [ $max_lebs -le 0 ]; then
        echo "Error: Max LEB count ($max_lebs) too small. Check partition/LEB size."
        exit 1
    fi
    echo "Max LEB Count: $max_lebs (Partition: $PARTITION_SIZE_BYTES / LEB: $leb_size - Overhead: $overhead_lebs)"

    cmd_args=(python3 "$CREATE_UBIFS_SCRIPT"
                    -o "$FINAL_IMAGE_PATH"
                    -d "$PREPARED_USERDATA_DIR"
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

    FINAL_IMAGE_PATH="$OUTPUT_DIR/userdata.ubifs"
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
        -s "$PARTITION_SIZE_BYTES" \
        -n "userdata"
    if [ ! -f "$cfg_path" ]; then
        echo "Error: Failed to generate ubinize config: $cfg_path"
        exit 1
    fi

    FINAL_IMAGE_PATH="$OUTPUT_DIR/userdata.ubi"
    echo "Creating ubi image: $FINAL_IMAGE_PATH ..."
    ubi_args=(python3 "$CREATE_UBI_SCRIPT"
                -o "$FINAL_IMAGE_PATH"
                -p "$BLOCK_SIZE_DEC"
                -m "$PAGE_SIZE_DEC"
                -c "$cfg_path")
    if [ -n "$UBINIZE_PATH" ]; then
        ubi_args+=("-b" "$UBINIZE_PATH")
    fi

    "${ubi_args[@]}"
}

create_ext4_image() {
    echo "Creating ext4 image: $FINAL_IMAGE_PATH ..."
    local cmd_args=(python3 "$CREATE_EXT4_SCRIPT"
                    -o "$FINAL_IMAGE_PATH"
                    -d "$PREPARED_USERDATA_DIR"
                    -s "$PARTITION_SIZE_STR")
    if [ -n "$MKE2FS_PATH" ]; then
        cmd_args+=("-m" "$MKE2FS_PATH")
    fi

    "${cmd_args[@]}"
}

create_squashfs_image() {
    echo "Creating squashfs image: $FINAL_IMAGE_PATH ..."
    local cmd_args=(python3 "$CREATE_SQUASH_SCRIPT"
                    -o "$FINAL_IMAGE_PATH"
                    -d "$PREPARED_USERDATA_DIR")
    if [ -n "$MKSQUASH_PATH" ]; then
        cmd_args+=("-q" "$MKSQUASH_PATH")
    fi

    "${cmd_args[@]}"
}

create_sparse_image() {
    echo "Converting to sparse image: $FINAL_IMAGE_PATH"
    local extension="${FINAL_IMAGE_PATH##*.}"
    local basename
    basename=$(basename "$FINAL_IMAGE_PATH" ".$extension")
    local sparse_image_path="$OUTPUT_DIR/${basename}_sparse.${extension}"

    if [ -n "$IMG2SIMG_PATH" ]; then
        python3 "$CREATE_SPARSE_SCRIPT" -i "$FINAL_IMAGE_PATH" -o "$sparse_image_path" -m "$IMG2SIMG_PATH"
    else
        python3 "$CREATE_SPARSE_SCRIPT" -i "$FINAL_IMAGE_PATH" -o "$sparse_image_path"
    fi

    if [ -f "$sparse_image_path" ]; then
        echo "Successfully created sparse image: $sparse_image_path"
        FINAL_IMAGE_PATH="$sparse_image_path"
    else
        echo "Error: Failed to create sparse image."
        exit 1
    fi
}

add_userdata_payload() {
    echo "Adding userdata payload ..."

    local package_cmd_args=("$PACKAGE_USERDATA_SCRIPT" -p "$PLATFORM" -T "$PREPARED_USERDATA_DIR")
    if [ "$FUSA_ENABLE" = true ]; then
        package_cmd_args+=("-f")
    fi
    if [ -n "$CROSS_ASANLIB_PATH" ]; then
        package_cmd_args+=("-a" "$CROSS_ASANLIB_PATH")
    fi
    bash "${package_cmd_args[@]}"

    if [ ! -d "$PREPARED_USERDATA_DIR" ]; then
        echo "Error: Payload directory not found: $PREPARED_USERDATA_DIR"
        exit 1
    fi
    echo "Payload directory: $PREPARED_USERDATA_DIR"
}

main() {
    parse_args "$@"
    prepare_environment
    parse_partition_size
    add_userdata_payload

    case "$FS_TYPE" in
        ubifs)
            FINAL_IMAGE_PATH="$OUTPUT_DIR/userdata.ubifs"
            parse_flash_yaml
            create_ubifs_image
            ;;
        ext4)
            FINAL_IMAGE_PATH="$OUTPUT_DIR/userdata.ext4"
            create_ext4_image
            ;;
        ubi)
            # The final image path is set within create_ubi_image
            parse_flash_yaml
            create_ubi_image
            ;;
        squash)
            FINAL_IMAGE_PATH="$OUTPUT_DIR/userdata.squashfs"
            create_squashfs_image
            ;;
        *)
            echo "Error: Internal error, unsupported fs_type '$FS_TYPE'"
            exit 1
            ;;
    esac

    if [ ! -f "$FINAL_IMAGE_PATH" ]; then
        echo "Error: Failed to create userdata image."
        exit 1
    fi

    if [ "$CONVERT_TO_SPARSE" = true ]; then
        create_sparse_image
    fi

    if [ -f "$FINAL_IMAGE_PATH" ]; then
        echo "Successfully created userdata image: $FINAL_IMAGE_PATH"
    else
        echo "Error: Failed to create userdata image."
        exit 1
    fi
}

main "$@"