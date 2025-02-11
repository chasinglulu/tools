#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025, Charleye
#
# This script is used to convert the partitions.json file to output.xml.
# It reads the JSON file, creates an XML structure, and writes it to the output file.
# Users can specify the project name, alias, input file, output file, and FDL-related
# parameters via command-line arguments.
#
# Usage:
#   python3 convert.py -n <project_name> -a <project_alias> -i <input_json> -o <output_xml>
#   python3 convert.py --name <project_name> --alias <project_alias> --input <input_json> --output <output_xml>
#
# Options:
#   -n, --name          Project name (default: M57H)
#   -a, --alias         Project alias (default: M57H)
#   -i, --input         Input JSON file (default: partitions.json)
#   -o, --output        Output XML file (default: output.xml)
#   -l, --fdl_level     FDL level (default: 2, choices: [1, 2])
#   -f1b, --fdl1_base   FDL1 base address (default: 0x400, type: str, help='FDL1 base address in hex')
#   -f1s, --fdl1_size   FDL1 size (default: 0x0, type: str, help='FDL1 size in hex')
#   -f2b, --fdl2_base   FDL2 base address (default: 0x50000000, type: str, help='FDL2 base address in hex')
#   -f2s, --fdl2_size   FDL2 size (default: 0x0, type: str, help='FDL2 size in hex')
#   -d, --debug         Enable debug output
#   -m, --mtdparts      Enable mtdparts string conversion
#   -t, --strategy      Partitions strategy (default: 1, choices: [0, 1])
#
# For any questions, please contact: wangkart@aliyun.com

import json
import xml.etree.ElementTree as ET
import argparse
import re
from collections import Counter

def write_xml_with_comments(xml_str, output_file):
    comments = '''<?xml version="1.0" encoding="UTF-8"?>
<!--  [tag] FDLLevel:                                                        -->
<!--        [attribute]   1, one level FDL for download                      -->
<!--                      2, two levels FDL for download                     -->
<!--  [tag] Partitions:                                                      -->
<!--        [attribute]   strategy: 0, not partition                         -->
<!--                                1, partition                             -->
<!--  [tag] Img:                                                             -->
<!--        [attribute]   name: GUI display                                  -->
<!--        [attribute] select: 0, GUI selected                              -->
<!--                            1, GUI not selected                          -->
<!--        [attribute]   flag: mask value combined by below options (|)     -->
<!--                            0x01, need input a file                      -->
<!--                            0x02, must be selected                       -->
<!--              [tag]     ID: Internel used, not changed                   -->
<!--              [tag]   Type: Internel used, not changed                   -->
<!--              [tag]   Auth:                                              -->
<!--                      [attribute] algo: 0, No Auth                       -->
<!--                                        1, MD5                           -->
<!--                                        2, crc16                         -->
<!--              [tag]   File: Download file name                           -->
<!--              [tag]   Description: GUI display                           -->
'''
    with open(output_file, 'w') as f:
        f.write(comments)
        f.write(xml_str)

def convert_to_mtdparts(data):
    unit_mapping = {
        "1M": 1024 * 1024,
        "512K": 512 * 1024,
        "1K": 1024,
        "1": 1,
        "1Sector": 512
    }
    unit_size = 1024  # Default unit size
    for item in data:
        if 'unit' in item:
            unit_size = unit_mapping.get(item['unit'], 1024)
            break
    mtdparts = ""
    partitions = next((item['partitions'] for item in data if 'partitions' in item), [])
    if not partitions:
        raise ValueError("No 'partitions' field found in the JSON data.")
    exclude_names = {"emmc", "nand", "nor", "hyper"}
    for partition in partitions:
        if partition['name'].lower() not in exclude_names:
            size_in_kb = int(partition['size']) * unit_size // 1024
            if size_in_kb < 1:
                raise ValueError(f"Partition size too small: {partition['name']} size is less than 1KB.")
            attrs = partition.get('attrs', '')
            mtdparts += f"{size_in_kb}K({partition['name']}){attrs},"
    return mtdparts.rstrip(',')

def is_hex(value):
    return re.fullmatch(r'0x[0-9a-fA-F]+', value) is not None

def indent(elem, level=0):
    i = "\n" + level * "  "
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + "  "
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for elem in elem:
            indent(elem, level + 1)
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
    else:
        if level and (not elem.tail or not elem.tail.strip()):
            elem.tail = i

# Parse input arguments
parser = argparse.ArgumentParser(
    description='Convert partitions.json to output.xml',
    formatter_class=argparse.ArgumentDefaultsHelpFormatter
)
parser.add_argument('-n', '--name', default='M57H', help='Project name')
parser.add_argument('-a', '--alias', default='M57H', help='Project alias')
parser.add_argument('-i', '--input', default='partitions.json', help='Input JSON file')
parser.add_argument('-o', '--output', default='output.xml', help='Output XML file')
parser.add_argument('-l', '--fdl_level', default='2', choices=['1', '2'], help='FDL level')
parser.add_argument('-f1b', '--fdl1_base', default='0x400', type=str, help='FDL1 base address in hex')
parser.add_argument('-f1s', '--fdl1_size', default='0x0', type=str, help='FDL1 size in hex')
parser.add_argument('-f2b', '--fdl2_base', default='0x50000000', type=str, help='FDL2 base address in hex')
parser.add_argument('-f2s', '--fdl2_size', default='0x0', type=str, help='FDL2 size in hex')
parser.add_argument('-d', '--debug', action='store_true', default=False, help='Enable debug output')
parser.add_argument('-m', '--mtdparts', action='store_true', default=False, help='Enable mtdparts string conversion')
parser.add_argument('-t', '--strategy', default='1', choices=['0', '1'], help='Partitions strategy')
args = parser.parse_args()

# Validate hex inputs
if not is_hex(args.fdl1_base):
    raise ValueError("FDL1 base address must be a valid hex value.")
if not is_hex(args.fdl1_size):
    raise ValueError("FDL1 size must be a valid hex value.")
if not is_hex(args.fdl2_base):
    raise ValueError("FDL2 base address must be a valid hex value.")
if not is_hex(args.fdl2_size):
    raise ValueError("FDL2 size must be a valid hex value.")

try:
    # Read JSON file
    with open(args.input, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON file: {e}")

    # Check for duplicate partition names
    partitions_data = next((item['partitions'] for item in data if 'partitions' in item), [])
    partition_names = [partition['name'] for partition in partitions_data]
    duplicates = [name for name, count in Counter(partition_names).items() if count > 1]
    if duplicates:
        raise ValueError(f"Duplicate partition names found in the JSON data: {', '.join(duplicates)}")

    # Convert unit field to corresponding value
    unit_mapping = {
        "1M": "0",
        "512K": "1",
        "1K": "2",
        "1": "3",
        "1Sector": "4"
    }
    unit_value = unit_mapping.get(next((item.get('unit') for item in data if 'unit' in item), "2"), "2")

    # Create XML structure
    config = ET.Element('Config')
    project = ET.SubElement(config, 'Project', alias=args.alias, name=args.name, version="1.0")
    fdl_level = ET.SubElement(project, 'FDLLevel')
    fdl_level.text = args.fdl_level
    partitions = ET.SubElement(project, 'Partitions', strategy=args.strategy, unit=unit_value)

    # Add partition information
    if not partitions_data:
        raise ValueError("No 'partitions' field found in the JSON data.")
    for partition in partitions_data:
        ET.SubElement(partitions, 'Partition', gap="0", id=partition['name'], size=partition['size'])

    # Add ImgList information
    img_list = ET.SubElement(project, 'ImgList')
    images = [
        {"flag": "2", "name": "INIT", "select": "1", "id": "INIT", "type": "INIT", "base": "0x0", "size": "0x0", "description": "Handshake with ROMCode"},
        {"flag": "3", "name": "FDL1", "select": "1", "id": "FDL1", "type": "FDL1", "base": args.fdl1_base, "size": args.fdl1_size, "description": "FDL1 image to download"}
    ]

    # Add FDL2 information if FDLLevel is 2
    if args.fdl_level == '2':
        images.append({
            "flag": "3",
            "name": "FDL2",
            "select": "1",
            "id": "FDL2",
            "type": "FDL2",
            "base": args.fdl2_base,
            "size": args.fdl2_size,
            "description": "FDL2 image to download"
        })

    # Add Img information from partitions.json
    exclude_names = {"emmc", "nand", "nor", "hyper"}
    for partition in partitions_data:
        if partition['name'].lower() not in exclude_names:
            images.append({
                "flag": "1",
                "name": partition['name'].upper(),
                "select": "1",
                "id": partition['name'].upper(),
                "type": "CODE",
                "base": "0x0",
                "size": "0x0",
                "description": f"This image is used for {partition['name']} partition."
            })

    # Convert partitions.json to mtdparts string if enabled
    if args.mtdparts:
        mtdparts_str = convert_to_mtdparts(data).lstrip()
        print("MTD Parts: ")
        print("                   mtdparts=" + mtdparts_str)
        print("    CONFIG_MTDPARTS_DEFAULT=" + mtdparts_str)

    # Debug output of images object content
    if args.debug:
        print("Images object content:")
        for img in images:
            print(img)

    for img in images:
        img_element = ET.SubElement(img_list, 'Img', flag=img["flag"], name=img["name"], select=img["select"])
        ET.SubElement(img_element, 'ID').text = img["id"]
        ET.SubElement(img_element, 'Type').text = img["type"]
        block = ET.SubElement(img_element, 'Block')
        if img["name"] not in ["INIT", "FDL1", "FDL2"]:
            block.set("id", img["name"].lower())
        ET.SubElement(block, 'Base').text = img["base"]
        ET.SubElement(block, 'Size').text = img["size"]
        ET.SubElement(img_element, 'File')
        ET.SubElement(img_element, 'Auth', algo="0")
        ET.SubElement(img_element, 'Description').text = img["description"]

    # Convert XML structure to string with indentation
    indent(config)
    xml_str = ET.tostring(config, encoding='utf-8').decode('utf-8')

    # Write XML file and add comments
    write_xml_with_comments(xml_str, args.output)

    print(f"XML file generated: {args.output}")

except Exception as e:
    print(f"An error occurred: {e}")
