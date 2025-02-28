'''
SPDX-License-Identifier: GPL-2.0+

This script parses a JSON file containing partition information and
retrieves the size of a specified partition, converting it to appropriate
units (GB, MB, KB, bytes) based on its size. It supports a debug mode for
more verbose output.

Copyright (C) 2025 Charleye <wangkart@aliyun.com>

'''
import json
import argparse

def get_partition_size(json_file, partition_name, debug=False):
    """
    Parses a JSON file to get the size of a specified partition and converts it based on the unit.

    Args:
        json_file (str): Path to the JSON file.
        partition_name (str): Name of the partition to query.
        debug (bool): Enable debug output.

    Returns:
        int: Converted partition size, or None if the partition is not found.
    """
    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        if debug:
            print(f"Error: File not found: {json_file}")
        return None
    except json.JSONDecodeError:
        if debug:
            print(f"Error: JSON file parsing failed: {json_file}")
        return None

    partitions_data = None
    for item in data:
        if isinstance(item, dict) and "partitions" in item:
            partitions_data = item["partitions"]
            break

    if not partitions_data:
        if debug:
            print("Error: No 'partitions' field found in the JSON file.")
        return None

    unit_data = None
    for item in data:
        if isinstance(item, dict) and "unit" in item:
            unit_data = item
            break

    if not unit_data:
        if debug:
            print("Error: No 'unit' field found in the JSON file.")
        return None

    unit_mapping = {
        "1M": 1024 * 1024,
        "512K": 512 * 1024,
        "1K": 1024,
        "1": 1,
        "1Sector": 512
    }

    unit = unit_data.get('unit', '1')  # Default unit is 1
    unit_value = unit_mapping.get(unit, 1)

    for partition in partitions_data:
        if partition['name'] == partition_name:
            size = int(partition['size'])
            if size <= 0:
                return None
            return size * unit_value

    if debug:
        print(f"Partition named '{partition_name}' not found.")
    return None


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Gets the size of a specified partition from a JSON file.")
    parser.add_argument("-f", "--json_file", help="Path to the JSON file", required=True)
    parser.add_argument("-p", "--partition_name", help="Name of the partition to query", required=True)
    parser.add_argument("-d", "--debug", action="store_true", help="Enable debug output")

    args = parser.parse_args()

    size = get_partition_size(args.json_file, args.partition_name, args.debug)

    if size is None:
        print(f"{args.partition_name} : 0")
        exit(0)

    if size % (1024 * 1024 * 1024) == 0:
        size_value = int(size / (1024 * 1024 * 1024))
        unit = "G"
        unit_long = "GB"
    elif size % (1024 * 1024) == 0:
        size_value = int(size / (1024 * 1024))
        unit = "M"
        unit_long = "MB"
    elif size % 1024 == 0:
        size_value = int(size / 1024)
        unit = "K"
        unit_long = "KB"
    else:
        size_value = size
        unit = ""
        unit_long = "bytes"

    output = f"{args.partition_name} : {size_value}{unit}" if not args.debug else f"{args.partition_name} : {size_value}{unit}"
    print(output)
