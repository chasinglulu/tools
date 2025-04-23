#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# Generates a configuration file for ubinize.
#

import sys
import argparse
import re

def generate_config(image_name="ubifs.img", vol_size="450MiB"):
    """Generates the ubinize configuration content."""
    config_content = f"""[ubifs]
mode=ubi
image={image_name}
vol_id=0
vol_size={vol_size}
vol_type=dynamic
vol_name=rootfs
vol_alignment=1
vol_flags=autoresize"""
    return config_content.strip()

def parse_and_format_size(value):
    """
    Parses size input (bytes as dec/hex, or KiB/MiB/GiB/KB/MB/GB format)
    and returns standardized KiB/MiB/GiB string.
    """
    value_str = str(value).strip()

    unit_match = re.match(r'^(\d+)([KMG])i?B$', value_str, re.IGNORECASE)
    if unit_match:
        number_str, unit_prefix = unit_match.groups()
        try:
            num_val = int(number_str)
            if num_val < 0:
                 raise ValueError("Number cannot be negative")
        except ValueError as e:
             raise argparse.ArgumentTypeError(f"Invalid number part '{number_str}' in size '{value_str}': {e}")

        standardized_unit = f"{unit_prefix.upper()}iB"
        return f"{num_val}{standardized_unit}"

    try:
        if value_str.lower().startswith('0x'):
            bytes_val = int(value_str, 16)
        else:
            bytes_val = int(value_str)
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"'{value_str}' is not a valid size format. Use decimal/hex bytes (e.g., 471859200, 0x1C200000) "
            f"or units like 1024KiB, 450MB, 2GiB."
        )

    if bytes_val < 0:
        raise argparse.ArgumentTypeError("Size cannot be negative.")

    GIB = 1 << 30
    MIB = 1 << 20
    KIB = 1 << 10

    if bytes_val == 0:
        return "0KiB"

    if bytes_val % KIB != 0:
        raise argparse.ArgumentTypeError(
            f"Byte value {bytes_val} ('{value_str}') must be a multiple of {KIB} (KiB)."
        )

    if bytes_val % GIB == 0:
        return f"{bytes_val // GIB}GiB"
    elif bytes_val % MIB == 0:
        return f"{bytes_val // MIB}MiB"
    else:
        return f"{bytes_val // KIB}KiB"

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Generate ubinize configuration file content.')
    parser.add_argument('-i', '--image', type=str, default='ubifs.img',
                        help='Specify the image filename (default: ubifs.img)')
    parser.add_argument('-s', '--vol_size', type=parse_and_format_size, default='450MiB',
                        help='Specify the volume size (e.g., 471859200, 0x1C200000, 450MB, 2GiB, 1024KB)')
    parser.add_argument('-o', '--output', type=str, default='ubinize.cfg',
                        help='Specify the output configuration file path (default: ubinize.cfg)')
    args = parser.parse_args()

    config_data = generate_config(image_name=args.image, vol_size=args.vol_size)

    try:
        with open(args.output, 'w') as f:
            f.write(config_data + '\n')
        print(f"Successfully generated {args.output}")
    except IOError as e:
        print(f"Error writing to file {args.output}: {e}", file=sys.stderr)
        sys.exit(1)
