#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025, Charleye
#
# This script is used to create an AXP file from an XML configuration file.
# It reads the XML file, copies the specified files, updates the XML content,
# and creates an AXP file as the output.
#
# Usage:
#   python3 create_axp.py -p <project_name> -o <output_axp> -x <xml_file> [files...]
#   python3 create_axp.py --project <project_name> --output <output_axp> --xml <xml_file> [files...]
#
# Options:
#   -p, --project       Set project name (default: M57H)
#   -o, --output        Set output .axp file (default: output.axp)
#   -x, --xml           XML configuration file (default: output.xml)
#   -v, --version       Set version (default: 1.0)
#   -d, --debug         Enable debug mode
#   -V, --verbose       Enable verbose output
#   -P, --partitions    Input image files in the format PARTITION_NAME=file_path
#                       e.g.,
#                         ATF_A=path/to/file1
#                         ATF_B=path/to/file2
#                         UBOOT_A=path/to/file3
#                         UBOOT_B=path/to/file4
#   -f, --files         Input image files
#
# For any questions, please contact: wangkart@aliyun.com

import os
import sys
import zipfile
import shutil
import xml.etree.ElementTree as ET
import hashlib
import argparse

def get_abspath(path):
    return os.path.normpath(os.path.abspath(path))

def get_fname(path):
    return os.path.basename(path)

def read_block_from_file(file, block_size):
    with open(file, 'rb') as f:
        while True:
            block = f.read(block_size)
            if block:
                yield block
            else:
                return

def calc_md5(file):
    m = hashlib.md5()
    for block in read_block_from_file(file, 10 * 1024 * 1024):
        m.update(block)
    return m.hexdigest()

def calc_crc16(file):
    crc16_table = [
        0x0000, 0xC0C1, 0xC181, 0x0140, 0xC301, 0x03C0, 0x0280, 0xC241,
        0xC601, 0x06C0, 0x0780, 0xC741, 0x0500, 0xC5C1, 0xC481, 0x0440,
        0xCC01, 0x0CC0, 0x0D80, 0xCD41, 0x0F00, 0xCFC1, 0xCE81, 0x0E40,
        0x0A00, 0xCAC1, 0xCB81, 0x0B40, 0xC901, 0x09C0, 0x0880, 0xC841,
        0xD801, 0x18C0, 0x1980, 0xD941, 0x1B00, 0xDBC1, 0xDA81, 0x1A40,
        0x1E00, 0xDEC1, 0xDF81, 0x1F40, 0xDD01, 0x1DC0, 0x1C80, 0xDC41,
        0x1400, 0xD4C1, 0xD581, 0x1540, 0xD701, 0x17C0, 0x1680, 0xD641,
        0xD201, 0x12C0, 0x1380, 0xD341, 0x1100, 0xD1C1, 0xD081, 0x1040,
        0xF001, 0x30C0, 0x3180, 0xF141, 0x3300, 0xF3C1, 0xF281, 0x3240,
        0x3600, 0xF6C1, 0xF781, 0x3740, 0xF501, 0x35C0, 0x3480, 0xF441,
        0x3C00, 0xFCC1, 0xFD81, 0x3D40, 0xFF01, 0x3FC0, 0x3E80, 0xFE41,
        0xFA01, 0x3AC0, 0x3B80, 0xFB41, 0x3900, 0xF9C1, 0xF881, 0x3840,
        0x2800, 0xE8C1, 0xE981, 0x2940, 0xEB01, 0x2BC0, 0x2A80, 0xEA41,
        0xEE01, 0x2EC0, 0x2F80, 0xEF41, 0x2D00, 0xEDC1, 0xEC81, 0x2C40,
        0xE401, 0x24C0, 0x2580, 0xE541, 0x2700, 0xE7C1, 0xE681, 0x2640,
        0x2200, 0xE2C1, 0xE381, 0x2340, 0xE101, 0x21C0, 0x2080, 0xE041,
        0xA001, 0x60C0, 0x6180, 0xA141, 0x6300, 0xA3C1, 0xA281, 0x6240,
        0x6600, 0xA6C1, 0xA781, 0x6740, 0xA501, 0x65C0, 0x6480, 0xA441,
        0x6C00, 0xACC1, 0xAD81, 0x6D40, 0xAF01, 0x6FC0, 0x6E80, 0xAE41,
        0xAA01, 0x6AC0, 0x6B80, 0xAB41, 0x6900, 0xA9C1, 0xA881, 0x6840,
        0x7800, 0xB8C1, 0xB981, 0x7940, 0xBB01, 0x7BC0, 0x7A80, 0xBA41,
        0xBE01, 0x7EC0, 0x7F80, 0xBF41, 0x7D00, 0xBDC1, 0xBC81, 0x7C40,
        0xB401, 0x74C0, 0x7580, 0xB541, 0x7700, 0xB7C1, 0xB681, 0x7640,
        0x7200, 0xB2C1, 0xB381, 0x7340, 0xB101, 0x71C0, 0x7080, 0xB041,
        0x5000, 0x90C1, 0x9181, 0x5140, 0x9301, 0x53C0, 0x5280, 0x9241,
        0x9601, 0x56C0, 0x5780, 0x9741, 0x5500, 0x95C1, 0x9481, 0x5440,
        0x9C01, 0x5CC0, 0x5D80, 0x9D41, 0x5F00, 0x9FC1, 0x9E81, 0x5E40,
        0x5A00, 0x9AC1, 0x9B81, 0x5B40, 0x9901, 0x59C0, 0x5880, 0x9841,
        0x8801, 0x48C0, 0x4980, 0x8941, 0x4B00, 0x8BC1, 0x8A81, 0x4A40,
        0x4E00, 0x8EC1, 0x8F81, 0x4F40, 0x8D01, 0x4DC0, 0x4C80, 0x8C41,
        0x4400, 0x84C1, 0x8581, 0x4540, 0x8701, 0x47C0, 0x4680, 0x8641,
        0x8201, 0x42C0, 0x4380, 0x8341, 0x4100, 0x81C1, 0x8081, 0x4040
    ]
    crc16 = 0
    for block in read_block_from_file(file, 10 * 1024 * 1024):
        for data in block:
            crc16 = (crc16 >> 8) ^ (crc16_table[(crc16 ^ data) & 0xFF])
    return hex(crc16)

def get_unique_filename(file_name, copied_files):
    dst_file = file_name
    if dst_file in copied_files:
        base, ext = os.path.splitext(dst_file)
        counter = 1
        while dst_file in copied_files:
            dst_file = f"{base}_{counter}{ext}"
            counter += 1
    copied_files.add(dst_file)
    return dst_file

def update_file_node(file, node_img, zip_dir, copied_files):
    file_name = get_fname(file)
    dst_file = get_unique_filename(file_name, copied_files)
    node_file = node_img.find('File')
    node_file.text = dst_file
    node_auth = node_img.find('Auth')
    algo = node_auth.get('algo')
    if algo and int(algo) > 0:
        file_path = os.path.join(zip_dir, dst_file)
        if int(algo) == 1:
            node_auth.text = calc_md5(file_path)
        elif int(algo) == 2:
            node_auth.text = calc_crc16(file_path)

def update_xml_content(tree, args, zip_dir, copied_files):
    """
    Update XML content based on provided arguments.

    Args:
        tree (ET.ElementTree): XML tree to update.
        args (argparse.Namespace): Arguments with project details, version, files, and partitions.
        zip_dir (str): Directory where the zip files are stored.
        copied_files (set): Set to track copied files.

    Raises:
        ValueError: If input files count doesn't match required image nodes.
    """
    root = tree.getroot()

    node_project = root.find('Project')
    node_project.set('name', args.name)
    if args.version:
        node_project.set('version', args.version)

    img_nodes = [img for img in root.iter('Img') if (int(img.get('flag', 0)) & 0x01) == 0x01]

    if args.files:
        for file, node_img in zip(args.files, img_nodes):
            update_file_node(file, node_img, zip_dir, copied_files)

    if args.partitions:
        partition_map = {p.split('=')[0]: p.split('=')[1] for p in args.partitions}
        for node_img in img_nodes:
            part_name = node_img.find('ID').text
            file = partition_map.get(part_name)
            if file:
                update_file_node(file, node_img, zip_dir, copied_files)

def make_zip(zip_dir, zip_path, verbose):
    """
    Create a zip file from a directory.

    Args:
        zip_dir (str): Directory to zip.
        zip_path (str): Output zip file path.
        verbose (bool): Print file names if True.

    Raises:
        Exception: On error, prints message and exits.
    """
    try:
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
            for root, _, files in os.walk(zip_dir):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, zip_dir)
                    if verbose:
                        print(f'Adding {file_path} to AXP {zip_path}')
                    zf.write(file_path, arcname)
    except Exception as e:
        print(f"Error creating AXP file {zip_path}: {e}")
        sys.exit(1)

def copy_file(src, dst, verbose):
    if verbose:
        print(f'Copying from {src} to {dst}')
    if os.path.isfile(src):
        shutil.copy(src, dst)
    elif os.path.isdir(src):
        shutil.copytree(src, dst)

def prepare_directories(xml_path, output_path):
    zip_dir = os.path.splitext(output_path)[0]
    if os.path.exists(output_path):
        os.remove(output_path)
    if os.path.exists(zip_dir):
        shutil.rmtree(zip_dir)
    os.mkdir(zip_dir)
    return zip_dir

def copy_files(args, root, zip_dir, copied_files):
    """
    Copies specified files to the destination directory.

    Args:
        args (argparse.Namespace): Command-line arguments.
        root (xml.etree.ElementTree.Element): XML root element.
        zip_dir (str): Destination directory.
        copied_files (set): Set of copied files.

    Returns:
        int: Total files copied.
    """
    total_files_copied = 0
    if args.partitions:
        partition_map = {p.split('=')[0]: p.split('=')[1] for p in args.partitions}
        for part_name, file_path in partition_map.items():
            dst_file = get_unique_filename(get_fname(file_path), copied_files)
            dst_path = os.path.join(zip_dir, dst_file)
            copy_file(file_path, dst_path, args.verbose)
            total_files_copied += 1

    files = [get_abspath(file) for file in args.files] if args.files else []
    if not files:
        files = [
            get_abspath(node_img.find('File').text)
            for node_img in root.iter('Img')
            if node_img.get('flag') and (int(node_img.get('flag')) & 0x01) == 0x01
            and node_img.find('File').text
        ]

    for file in files:
        dst_file = get_unique_filename(get_fname(file), copied_files)
        dst_path = os.path.join(zip_dir, dst_file)
        copy_file(file, dst_path, args.verbose)
        total_files_copied += 1

    return total_files_copied

def copy_xml_file(xml_path, zip_dir, verbose):
    xml_dst_path = os.path.join(zip_dir, get_fname(xml_path))
    if verbose:
        print(f'Copying from {xml_path} to {xml_dst_path}')
    shutil.copy(xml_path, xml_dst_path)
    return xml_dst_path

def create_axp(args):
    """
    Creates an AXP file from the given XML file.

    Args:
        args: argparse.Namespace with attributes:
            - xml (str): Input XML file path.
            - output (str): Output AXP file path.
            - verbose (bool): Enable detailed logs.
            - debug (bool): Retain temporary directories for debugging.

    Raises:
        Exception: On error during AXP creation.

    Steps:
        1. Parse XML file.
        2. Prepare directories.
        3. Copy referenced files.
        4. Copy XML file.
        5. Update XML content.
        6. Write updated XML.
        7. Create ZIP archive.
        8. Clean up unless in debug mode.

    Prints:
        - Detailed logs if verbose.
        - Success message on completion.
        - Error message and exits on exception.
    """
    try:
        xml_path = get_abspath(args.xml)
        output_path = get_abspath(args.output)

        tree = ET.parse(xml_path)
        root = tree.getroot()

        zip_dir = prepare_directories(xml_path, output_path)

        if args.verbose:
            print('Starting file copy...')

        copied_files = set()
        total_files_copied = copy_files(args, root, zip_dir, copied_files)

        xml_dst_path = copy_xml_file(xml_path, zip_dir, args.verbose)
        total_files_copied += 1

        if args.verbose:
            print(f'Total {total_files_copied} files copied.')

        copied_files.clear()
        update_xml_content(tree, args, zip_dir, copied_files)
        tree.write(xml_dst_path)
        make_zip(zip_dir, output_path, args.verbose)
        if not args.debug:
            shutil.rmtree(zip_dir)
        print(f"AXP file created successfully at {output_path}.")
    except Exception as e:
        print(f"Error creating AXP from XML: {e}")
        sys.exit(1)

def parse_args():
    parser = argparse.ArgumentParser(
        description='Create AXP from XML configuration.',
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument('-n', '--name', default='M57H', help='Set project name')
    parser.add_argument('-o', '--output', default='output.axp', help='Set output .axp file')
    parser.add_argument('-x', '--xml', default='output.xml', help='XML configuration file')
    parser.add_argument('-v', '--version', default='1.0', help='Set version')
    parser.add_argument('-d', '--debug', action='store_true', default=False, help='Enable debug mode')
    parser.add_argument('-V', '--verbose', action='store_true', default=False, help='Enable verbose output')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('-P', '--partitions', nargs='*',
                       help=('Input image files in the format PARTITION_NAME=file_path\n'
                             'e.g.,\n'
                             '  ATF_A=path/to/file1\n'
                             '  ATF_B=path/to/file2\n'
                             '  UBOOT_A=path/to/file3\n'
                             '  UBOOT_B=path/to/file4'))
    group.add_argument('-f', '--files', nargs='*', help='Input image files')
    args = parser.parse_args()

    # Validate file paths
    if not os.path.exists(args.xml):
        parser.error(f"The XML file '{args.xml}' does not exist.")
    if not os.path.isfile(args.xml):
        parser.error(f"The XML file '{args.xml}' is not a valid file.")

    # Check for unique <name> attribute and <ID> of <Img> node
    try:
        tree = ET.parse(args.xml)
        root = tree.getroot()
        names = set()
        ids = set()
        for img in root.iter('Img'):
            name = img.get('name')
            if name in names:
                parser.error(f"Duplicate <name> attribute found in <Img> node: {name}")
            names.add(name)
            img_id = img.find('ID').text
            if img_id in ids:
                parser.error(f"Duplicate <ID> found in <Img> node: {img_id}")
            ids.add(img_id)
    except ET.ParseError as e:
        parser.error(f"Error parsing XML file: {e}")

    # Validate partition arguments
    if args.partitions:
        part_names = set()
        for part in args.partitions:
            if '=' not in part:
                parser.error(f"Invalid partition format: {part}. Expected format PARTITION_NAME=file_path")
            part_name, file_path = part.split('=', 1)
            if part_name in part_names:
                parser.error(f"Duplicate PARTITION_NAME found: {part_name}")
            part_names.add(part_name)
            if not os.path.exists(file_path):
                parser.error(f"The image file '{file_path}' does not exist.")
            if not os.path.isfile(file_path):
                parser.error(f"The image file '{file_path}' is not a valid file.")

        # Check if partition names match IDs in XML
        invalid_parts = [part_name for part_name in part_names if part_name not in ids]
        if invalid_parts:
            parser.error(f"PARTITION_NAME: '{', '.join(invalid_parts)}' do not match any ID in the XML file.")

    # Validate files arguments
    if args.files:
        for file in args.files:
            if not os.path.exists(file):
                parser.error(f"The input file '{file}' does not exist.")
            if not os.path.isfile(file):
                parser.error(f"The input file '{file}' is not a valid file.")

    # Validate input files count matches required image nodes
    img_nodes = [img for img in root.iter('Img') if (int(img.get('flag', 0)) & 0x01) == 0x01]
    input_files = args.files if args.files else args.partitions
    if len(input_files) != len(img_nodes):
        parser.error(f"Mismatch: {len(input_files)} input image files vs {len(img_nodes)} required image nodes.")

    return args

def main():
    args = parse_args()
    create_axp(args)

if __name__ == "__main__":
    main()
