#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# Generates a binary partition table image from a JSON definition file.
#

import json
import struct
import zlib
import argparse
import os

# struct disk_partition {
#   lbaint_t start;    // (u64) Starting LBA of the partition
#   lbaint_t size;     // (u64) Size of the partition in LBAs
#   uchar    name[32]; // (32s) Partition name (null-terminated string)
#   int      bootable; // (s32) Bootable flag (e.g., 0 or 1)
#   int      has_image; // (s32) Indicate partition has image or not
# };
#
# Total size per partition entry = 8 + 8 + 32 + 4 + 4 = 56 bytes

# struct part_image {
#    __le32 magic;
#    __le32 version;
#    __le32 crc32;
#    __le32 blksz;
#    __le32 number;
#    struct disk_partition parts[];
# }

# Constants for the partition table header
MAGIC_NUMBER = 0x54524150  # "PART" in little-endian (P=50, A=41, R=52, T=54)
VERSION = 1
PART_NAME_LEN = 32
DEFAULT_BLKSZ = 512

# Format strings for struct packing (little-endian)
# Header: magic, version, crc32, blksz, number_of_partitions
HEADER_FORMAT = "<IIIII"
# Partition entry: start, size, name, bootable, has_image
PARTITION_ENTRY_FORMAT = f"<QQ{PART_NAME_LEN}sii"

UNIT_MULTIPLIERS = {
    "B": 1,
    "BYTE": 1,
    "K": 1024, "KB": 1024, "KIB": 1024, "1K": 1024,
    "M": 1024 * 1024, "MB": 1024 * 1024, "MIB": 1024 * 1024,
    "G": 1024 * 1024 * 1024, "GB": 1024 * 1024 * 1024, "GIB": 1024 * 1024 * 1024,
    "SECTOR": DEFAULT_BLKSZ
}

def get_unit_multiplier(unit_str):
    unit_str_upper = unit_str.upper()
    if unit_str_upper in UNIT_MULTIPLIERS:
        return UNIT_MULTIPLIERS[unit_str_upper]
    else:
        raise ValueError(f"Unknown unit: {unit_str}")

def str_to_bytes(s, length, encoding='utf-8'):
    encoded_s = s.encode(encoding, errors='ignore')
    return encoded_s[:length].ljust(length, b'\0')

def create_partition_image(json_path, image_path):
    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: JSON file not found at {json_path}")
        return False
    except json.JSONDecodeError as e:
        print(f"Error: Could not decode JSON from {json_path}: {e}")
        return False
    except Exception as e:
        print(f"Error reading JSON file {json_path}: {e}")
        return False

    if not isinstance(data, list) or len(data) < 1:
        print("Error: JSON format is invalid. Expected a list.")
        return False

    partitions_info_list = None
    unit_str = None

    for item in data:
        if isinstance(item, dict):
            if "partitions" in item:
                partitions_info_list = item["partitions"]
            if "unit" in item:
                unit_str = item["unit"]

    if partitions_info_list is None:
        print("Error: 'partitions' key not found in JSON data.")
        return False
    if not isinstance(partitions_info_list, list):
        print("Error: 'partitions' value must be a list.")
        return False
    if unit_str is None:
        print("Error: 'unit' key not found in JSON data.")
        return False

    try:
        unit_multiplier = get_unit_multiplier(unit_str)
    except ValueError as e:
        print(f"Error: {e}")
        return False

    packed_partitions_data = []
    current_block_start = 0

    for p_info in partitions_info_list:
        if not isinstance(p_info, dict):
            print(f"Warning: Partition entry is not a dictionary: {p_info}. Skipping.")
            continue

        name = p_info.get("name", "")
        size_str = p_info.get("size", "0")
        bootable = 0
        flags = p_info.get("flags", "")
        has_image = 1 if "no-image" not in flags else 0

        try:
            size_val = int(size_str)
        except ValueError:
            print(f"Warning: Invalid size '{size_str}' for partition '{name}'. Using 0.")
            size_val = 0

        size_in_bytes = size_val * unit_multiplier
        if DEFAULT_BLKSZ == 0:
             print(f"Error: DEFAULT_BLKSZ is zero.")
             return False

        if size_in_bytes == 0:
            size_in_blocks = 0
        else:
            size_in_blocks = (size_in_bytes + DEFAULT_BLKSZ - 1) // DEFAULT_BLKSZ

        part_start_lba = current_block_start
        part_size_lba = size_in_blocks
        name_bytes = str_to_bytes(name, PART_NAME_LEN)

        packed_entry = struct.pack(PARTITION_ENTRY_FORMAT,
                                   part_start_lba,
                                   part_size_lba,
                                   name_bytes,
                                   bootable,
                                   has_image)
        packed_partitions_data.append(packed_entry)
        current_block_start += part_size_lba

    num_partitions = len(packed_partitions_data)

    # Data for CRC calculation: blksz, number_of_partitions + all partition_data
    # The __le32 blksz and __le32 number fields themselves are part of the CRC payload.
    crc_payload_list = [struct.pack("<I", DEFAULT_BLKSZ), struct.pack("<I", num_partitions)] + packed_partitions_data
    crc_payload = b"".join(crc_payload_list)

    calculated_crc32 = zlib.crc32(crc_payload) & 0xFFFFFFFF
    header_data = struct.pack(HEADER_FORMAT,
                              MAGIC_NUMBER,
                              VERSION,
                              calculated_crc32,
                              DEFAULT_BLKSZ,
                              num_partitions)

    try:
        with open(image_path, 'wb') as f_img:
            f_img.write(header_data)
            for entry_data in packed_partitions_data:
                f_img.write(entry_data)
        print(f"Partition image successfully created at {image_path}")
        return True
    except IOError as e:
        print(f"Error: Could not write image file to {image_path}: {e}")
        return False
    except Exception as e:
        print(f"Error writing image file {image_path}: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description="Generate a binary partition image from a JSON file.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("-j", "--json",
                        dest="json",
                        help="Path to the input JSON partition definition file.",
                        required=True)
    parser.add_argument("-o", "--output_image",
                        dest="output_image",
                        help="Path for the output binary partition image.",
                        required=True)

    args = parser.parse_args()

    if not os.path.isfile(args.json):
        print(f"Error: Input JSON file not found: {args.json}")
        return

    create_partition_image(args.json, args.output_image)

if __name__ == "__main__":
    main()
