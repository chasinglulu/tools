#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0+
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# converts a JSON partition layout to an XML configuration for flashing tools.
#

import json
import xml.etree.ElementTree as ET
import argparse
import re
from collections import Counter
import os

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
<!--              [tag]     ID: Internal used, not changed                   -->
<!--              [tag]   Type: Internal used, not changed                   -->
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

def convert_to_mtdparts(json_partitions, json_unit):
    unit_mapping = {
        "1M": 1024 * 1024,
        "512K": 512 * 1024,
        "1K": 1024,
        "1": 1,
        "1Sector": 512
    }
    unit_size = unit_mapping.get(json_unit, 1024)
    mtdparts = ""
    exclude_names = {"emmc", "nand", "nor", "hyper"}
    for partition in json_partitions:
        if partition['name'].lower() not in exclude_names:
            size_str = partition['size']
            if isinstance(size_str, str) and size_str.startswith('0x'):
                size = int(size_str, 16)
            else:
                size = int(size_str)
            size_in_kb = size * unit_size // 1024
            if size_in_kb < 1:
                raise ValueError(f"Partition size too small: {partition['name']} size is less than 1KB.")
            attrs = partition.get('attrs', '')
            mtdparts += f"{size_in_kb}K({partition['name']}){attrs},"
    return mtdparts.rstrip(',')

def handle_mtdparts(args, json_partitions, json_unit):
    if args.mtdparts or args.mtdparts_file:
        mtdparts_str = convert_to_mtdparts(json_partitions, json_unit).lstrip()
        if args.mtdparts:
            print("MTD Parts: ")
            print("                   mtdparts=" + mtdparts_str)
            print("    CONFIG_MTDPARTS_DEFAULT=" + mtdparts_str)
        if args.mtdparts_file:
            try:
                with open(args.mtdparts_file, 'w') as f:
                    f.write('PARTITION="' + mtdparts_str + '"\n')
                print(f"MTD parts string written to: {args.mtdparts_file}")
            except Exception as e:
                print(f"Error writing to {args.mtdparts_file}: {e}")

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

def parse_arguments():
    parser = argparse.ArgumentParser(
        description='Convert partitions.json to output.xml',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument('-n', '--name', default='M57H', help='Project name')
    parser.add_argument('-a', '--alias', default=None, help='Project alias')
    parser.add_argument('-i', '--input', default='partitions.json', help='Input JSON file')
    parser.add_argument('-o', '--output', default='output.xml', help='Output XML file')
    parser.add_argument('-mf', '--mtdparts_file', default=None, help='Output file for mtdparts string')
    parser.add_argument('-l', '--fdl_level', default='2', choices=['1', '2'], help='FDL level')
    parser.add_argument('-eb', '--eip_base', default='0x3EA000', type=str, help='EIP base address in hex')
    parser.add_argument('-es', '--eip_size', default='0x0', type=str, help='EIP size in hex')
    parser.add_argument('-f1b', '--fdl1_base', default='0x200000', type=str, help='FDL1 base address in hex')
    parser.add_argument('-f1s', '--fdl1_size', default='0x0', type=str, help='FDL1 size in hex')
    parser.add_argument('-f2b', '--fdl2_base', default='0x14000A00', type=str, help='FDL2 base address in hex')
    parser.add_argument('-f2s', '--fdl2_size', default='0x0', type=str, help='FDL2 size in hex')
    parser.add_argument('-d', '--debug', action='store_true', default=False, help='Enable debug output')
    parser.add_argument('-m', '--mtdparts', action='store_true', default=False, help='Enable mtdparts string conversion')
    parser.add_argument('-t', '--strategy', default='1', choices=['0', '1'], help='Partitions strategy')
    parser.add_argument('-s', '--secureboot', action='store_true', default=False, help='Include EIP image in ImgList')
    parser.add_argument('-v', '--version', default='1.0', help='Project version')
    args = parser.parse_args()

    # Validate input file
    if not os.path.exists(args.input):
        raise ValueError(f"The input file '{args.input}' does not exist.")
    if not os.path.isfile(args.input):
        raise ValueError(f"The input file '{args.input}' is not a valid file.")
    if not args.input.endswith('.json'):
        raise ValueError("The input file must be a JSON suffix file.")

    # Validate hex inputs
    if not is_hex(args.fdl1_base):
        raise ValueError("FDL1 base address must be a valid hex value.")
    if not is_hex(args.fdl1_size):
        raise ValueError("FDL1 size must be a valid hex value.")
    if not is_hex(args.fdl2_base):
        raise ValueError("FDL2 base address must be a valid hex value.")
    if not is_hex(args.fdl2_size):
        raise ValueError("FDL2 size must be a valid hex value.")
    if args.secureboot:
        if not is_hex(args.eip_base):
            raise ValueError("EIP base address must be a valid hex value.")
        if not is_hex(args.eip_size):
            raise ValueError("EIP size must be a valid hex value.")

    return args

def load_and_validate_json(input_file):
    with open(input_file, 'r') as f:
        try:
            json_data = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON file: {e}")

    json_partitions = next((item['partitions'] for item in json_data if 'partitions' in item), None)
    if json_partitions is None:
        raise ValueError("The JSON file does not contain 'partitions' field.")

    json_unit = next((item.get('unit') for item in json_data if 'unit' in item), None)
    if json_unit is None:
        raise ValueError("The JSON file does not contain 'unit' field.")

    partition_names = [partition['name'] for partition in json_partitions]
    duplicates = [name for name, count in Counter(partition_names).items() if count > 1]
    if duplicates:
        raise ValueError(f"Duplicate partition names found in the JSON data: {', '.join(duplicates)}")

    for partition in json_partitions:
        if 'flags' in partition:
            flags_value = partition['flags']
            if flags_value not in ['no-image', 'selected']:
                raise ValueError(f"Invalid value for 'flags' field: {flags_value}. Allowed values are 'no-image' and 'selected'.")

        if 'attrs' in partition:
            attrs_value = partition['attrs']
            allowed_attrs = ['ro', 'bootable', 'ro,bootable', 'bootable,ro']
            if attrs_value not in allowed_attrs:
                raise ValueError(f"Invalid value for 'attrs' field: {attrs_value}. Allowed values are 'ro', 'bootable', 'ro,bootable', and 'bootable,ro'.")

    return json_partitions, json_unit

def create_xml_elements(args, unit_value):
    config_elem = ET.Element('Config')
    alias = args.name if args.alias is None else args.alias
    project_elem = ET.SubElement(config_elem, 'Project', alias=alias, name=args.name, version=args.version)
    fdl_elem = ET.SubElement(project_elem, 'FDLLevel')
    fdl_elem.text = args.fdl_level
    partitions_elem = ET.SubElement(project_elem, 'Partitions', strategy=args.strategy, unit=unit_value)
    return config_elem, project_elem, partitions_elem

def add_partitions(partitions_elem, json_partitions):
    for partition in json_partitions:
        size_str = partition['size']
        if isinstance(size_str, str) and size_str.startswith('0x'):
            size = str(int(size_str, 16))
        else:
            size = size_str
        ET.SubElement(partitions_elem, 'Partition', gap="0", id=partition['name'], size=size)

def generate_images(args, json_partitions):
    images = [
        {"flag": "2", "name": "INIT", "select": "1", "id": "INIT", "type": "INIT", "base": "0x0", "size": "0x0", "description": "Handshake with ROMCode"}
    ]

    if args.secureboot:
        images.append({
            "flag": "3",
            "name": "EIP",
            "select": "1",
            "id": "EIP",
            "type": "EIP",
            "base": args.eip_base,
            "size": args.eip_size,
            "description": "EIP image for secure boot"
        })

    images.append({
        "flag": "3",
        "name": "FDL1",
        "select": "1",
            "id": "FDL1",
            "type": "FDL1",
            "base": args.fdl1_base,
            "size": args.fdl1_size,
            "description": "FDL1 image to download"
    })

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

    exclude_names = {"emmc", "nand", "nor", "hyper"}
    for partition in json_partitions:
        if partition['name'].lower() not in exclude_names:
            # Check if the partition has the 'flags' key and if it's set to 'no-image'
            # Skip partitions marked as 'no-image'
            if 'flags' in partition and 'no-image' in partition['flags']:
                continue

            # Determine flag_value based on flags
            # Default: requires file (0x01) -> 1
            flag_value = "1"
            if 'flags' in partition and 'selected' in partition['flags']:
                 # If 'selected' flag is present, it requires file (0x01) and must be selected (0x02) -> 3
                flag_value = "3"

            # Determine select_value based on gui_select first
            select_value = "1"
            if 'gui_select' in partition:
                gui_select_val = str(partition['gui_select']).lower()
                if gui_select_val == '0' or gui_select_val == 'false':
                    select_value = "0"

            images.append({
                "flag": flag_value,
                "name": partition['name'].upper(),
                "select": select_value,
                "id": partition['name'].upper(),
                "type": "CODE",
                "base": "0x0",
                "size": "0x0",
                "description": f"This image is used for {partition['name']} partition."
            })

    return images

def append_images(img_list_elem, images):
    for img in images:
        img_elem = ET.SubElement(img_list_elem, 'Img', flag=img["flag"], name=img["name"], select=img["select"])
        ET.SubElement(img_elem, 'ID').text = img["id"]
        ET.SubElement(img_elem, 'Type').text = img["type"]
        block_elem = ET.SubElement(img_elem, 'Block')
        if img["name"] not in ["INIT", "FDL1", "FDL2", "EIP"]:
            block_elem.set("id", img["name"].lower())
        ET.SubElement(block_elem, 'Base').text = img["base"]
        ET.SubElement(block_elem, 'Size').text = img["size"]
        ET.SubElement(img_elem, 'File')
        ET.SubElement(img_elem, 'Auth', algo="0")
        ET.SubElement(img_elem, 'Description').text = img["description"]

def create_xml_structure(args, json_partitions, json_unit):
    unit_mapping = {
        "1M": "0",
        "512K": "1",
        "1K": "2",
        "1": "3",
        "1Sector": "4"
    }
    unit_value = unit_mapping.get(json_unit, "2")

    config_elem, project_elem, partitions_elem = create_xml_elements(args, unit_value)
    add_partitions(partitions_elem, json_partitions)
    img_list_elem = ET.SubElement(project_elem, 'ImgList')
    images = generate_images(args, json_partitions)

    # Print the list of image names that meet the condition
    image_names = [img['name'] for img in images if int(img['flag']) & 0x01 == 0x01]
    print("Image names: " + " ".join(image_names))

    if args.debug:
        print("Images object content:")
        for img in images:
            print(img)

    append_images(img_list_elem, images)
    indent(config_elem)
    return ET.tostring(config_elem, encoding='utf-8').decode('utf-8')

def main():
    args = parse_arguments()
    json_partitions, json_unit = load_and_validate_json(args.input)
    xml_str = create_xml_structure(args, json_partitions, json_unit)
    write_xml_with_comments(xml_str, args.output)
    print(f"XML file generated: {args.output}")
    handle_mtdparts(args, json_partitions, json_unit)

if __name__ == "__main__":
    main()
