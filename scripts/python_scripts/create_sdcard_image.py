#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#
# This script is used to create a image zip file to flash
# device partitions vid SDCard.
#

import os
import sys
import zipfile
import shutil
import argparse
import hashlib

def get_abspath(path):
    return os.path.normpath(os.path.abspath(path))

def get_fname(path):
    return os.path.basename(path)

def copy_file(src, dst, verbose):
    if verbose:
        print(f'Copying from {src} to {dst}')
    if os.path.isfile(src):
        shutil.copy(src, dst)
    elif os.path.isdir(src):
        shutil.copytree(src, dst)

def read_block_from_file(file, block_size):
    with open(file, 'rb') as f:
        while True:
            block = f.read(block_size)
            if block:
                yield block
            else:
                return

def calc_sha1(file_path):
    sha1 = hashlib.sha1()
    for block in read_block_from_file(file_path, 10 * 1024 * 1024): # Read in 10MB chunks
        sha1.update(block)
    return sha1.hexdigest()

def create_zip(zip_dir, zip_path, verbose):
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
                        print(f'Adding {file_path} to zip {zip_path}')
                    zf.write(file_path, arcname)
    except Exception as e:
        print(f"Error creating zip file {zip_path}: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(
        description='Create a zip file from specified files.',
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument('-o', '--output', default='sdcard.zip', help='Set output .zip file')
    parser.add_argument('-P', '--partitions', nargs='+', required=True,
                       help=('Input files in the format PARTITION_NAME=file_path\n'
                             'e.g.,\n'
                             '  BOOT=path/to/boot.img\n'
                             '  SYSTEM=path/to/system.img'))
    parser.add_argument('-v', '--verbose', action='store_true', default=False, help='Enable verbose output')
    parser.add_argument('-d', '--debug', action='store_true', default=False, help='Enable debug mode (keeps temporary directory)')
    args = parser.parse_args()

    # Validate partition arguments and file existence
    partition_map = {}
    partition_names_seen = set()
    for part in args.partitions:
        if '=' not in part:
            parser.error(f"Invalid partition format: {part}. Expected format PARTITION_NAME=file_path")
        part_name, file_path = part.split('=', 1)
        if part_name in partition_names_seen:
            parser.error(f"Duplicate PARTITION_NAME found: {part_name}")
        partition_names_seen.add(part_name)
        file_path = get_abspath(file_path)
        if not os.path.exists(file_path):
            parser.error(f"The file '{file_path}' does not exist.")
        if not os.path.isfile(file_path):
            parser.error(f"The file '{file_path}' is not a valid file.")
        partition_map[part_name] = file_path

    # Create a temporary directory
    output_fullpath = get_abspath(args.output)
    # zip_dir will be the output path without its extension
    zip_dir = os.path.splitext(output_fullpath)[0]

    # Remove existing output file if it exists
    if os.path.exists(output_fullpath):
        os.remove(output_fullpath)

    if os.path.exists(zip_dir):
        shutil.rmtree(zip_dir)
    os.makedirs(zip_dir)

    # Copy files to the temporary directory
    copied_file_paths = []
    for part_name, file_path in partition_map.items():
        _, ext = os.path.splitext(file_path)
        dst_filename = part_name.lower() + ext
        dst_path = os.path.join(zip_dir, dst_filename)
        copy_file(file_path, dst_path, args.verbose)
        copied_file_paths.append(dst_path)

    # Generate sha1sum.txt
    sha1sum_file_path = os.path.join(zip_dir, "sha1sum.txt")
    with open(sha1sum_file_path, 'w') as f_sha1:
        for fp in copied_file_paths:
            sha1_hash = calc_sha1(fp)
            f_sha1.write(f"{sha1_hash}  {get_fname(fp)}\n")

    if args.verbose:
        print(f"Generated sha1sum.txt at {sha1sum_file_path}")

    # Create the zip file
    create_zip(zip_dir, args.output, args.verbose)

    # Remove the temporary directory
    if not args.debug:
        shutil.rmtree(zip_dir)

    print(f"Zip file created successfully at {args.output}.")

if __name__ == "__main__":
    main()