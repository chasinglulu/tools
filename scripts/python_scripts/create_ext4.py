#!/usr/bin/env python3

import argparse
import subprocess
import sys
import os
import re

# ANSI escape codes for colored output
RED = "\033[91m"
RESET = "\033[0m"

def check_command_exists(command):
    """
    Checks if a command exists.

    Args:
        command (str): The command to check.

    Returns:
        bool: True if the command exists, False otherwise.
    """
    try:
        subprocess.run([command], check=False, capture_output=True)
        return True
    except FileNotFoundError:
        return False

def get_mke2fs_version(mke2fs_cmd):
    """
    Gets the version of mke2fs.

    Args:
        mke2fs_cmd (str): Path to the mke2fs executable.

    Returns:
        str: The version of mke2fs, or None if the version cannot be determined.
    """
    try:
        result = subprocess.run([mke2fs_cmd, "-V"], capture_output=True, text=True, check=False)
        output = result.stderr
        match = re.search(r"mke2fs\s+(\d+\.\d+)", output)
        if match:
            return match.group(1)
        return None
    except Exception:
        return None

def create_ext4_image(options):
    """
    Creates an ext4 image from a directory.

    Args:
        options (dict): A dictionary containing the following keys:
            output_image (str): Path to the output image file.
            source_dir (str): Path to the source directory.
            size (str): Size of the image (default: 20M).
            volume_label (str, optional): Volume label for the image. Defaults to "".
            mke2fs (str, optional): Path to the mke2fs executable. Defaults to None.
    """

    mke2fs_cmd = os.path.join(options.get("mke2fs", ""), "mke2fs") if options.get("mke2fs") else "mke2fs"

    if not check_command_exists(mke2fs_cmd):
        if options.get("mke2fs"):
            print(f"Error: {mke2fs_cmd} command not found.")
            print(f"Please provide the correct path. Example: {os.path.dirname(options['mke2fs'])}/mke2fs")
        else:
            print(f"Error: {mke2fs_cmd} command not found.")
            print("Please install it, e.g., with: sudo apt-get install e2fsprogs")
        sys.exit(1)

    mke2fs_version = get_mke2fs_version(mke2fs_cmd)
    if mke2fs_version:
        print(f"mke2fs version: {mke2fs_version}")
    else:
        print("Could not determine mke2fs version.")

    if mke2fs_version and float(mke2fs_version) >= 1.46:
        print(f"{RED}Warning: mke2fs version >= 1.46 may encounter errors.\n"
              f"       If the ext4 image creation fails, please check if the size\n"
              f"       specified in partitions.json is too small.{RESET}")

    mkfs_command = [mke2fs_cmd, "-F", "-N", "0", "-O", "64bit", "-d", options["source_dir"], "-m", "5", "-r", "1", "-t", "ext4", options["output_image"], options["size"]]

    if options.get("volume_label"):
        mkfs_command = [mke2fs_cmd, "-L", options["volume_label"], "-F", "-N", "0", "-O", "64bit", "-d", options["source_dir"], "-m", "5", "-r", "1", "-t", "ext4", options["output_image"], options["size"]]

    try:
        subprocess.run(mkfs_command, check=True)
        print(f"Successfully created ext4 image: {options['output_image']}")
    except subprocess.CalledProcessError as e:
        print(f"Error creating ext4 image: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Create an ext4 image from a directory.")
    parser.add_argument("-o", "--output", dest="output_image", help="The output image filename")
    parser.add_argument("-s", "--size", default="20M", help="Size of the image (default: 20M)")
    parser.add_argument("-l", "--label", default="", dest="volume_label", help="Volume label")
    parser.add_argument("-d", "--dir", required=True, dest="source_dir", help="Source directory")
    parser.add_argument("-m", "--mke2fs", dest="mke2fs", help="Path to the mke2fs executable")

    args = parser.parse_args()

    options = vars(args)
    create_ext4_image(options)

if __name__ == "__main__":
    main()