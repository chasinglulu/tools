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
            mke2fs (str, optional): Path to the mke2fs executable directory. Defaults to None.
    """

    mke2fs_cmd = None
    specific_mke2fs_path = options.get("mke2fs")

    if specific_mke2fs_path:
        potential_cmd = os.path.join(specific_mke2fs_path, "mke2fs")
        if check_command_exists(potential_cmd):
            mke2fs_cmd = potential_cmd
            print(f"Using '{specific_mke2fs_path}/mke2fs'")
        else:
            print(f"Warning: mke2fs not found at path: {specific_mke2fs_path}. Trying system path.")

    if mke2fs_cmd is None:
        default_cmd = "mke2fs"
        if check_command_exists(default_cmd):
            mke2fs_cmd = default_cmd
            print(f"Using system mke2fs")
        else:
            error_msg = f"Error: {RED}'mke2fs' command not found.{RESET}\n"
            if specific_mke2fs_path:
                error_msg += f"  - Check specified path: {specific_mke2fs_path}\n"
            error_msg += "  - Check system path: /usr/sbin or /sbin or /usr/local/sbin\n"
            error_msg += "Please install it, e.g., with: sudo apt-get install e2fsprogs "
            error_msg += "or provide a valid path using the -m option."
            print(error_msg)
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

    mkfs_command_base = [mke2fs_cmd, "-F", "-N", "0", "-O", "64bit", "-d", options["source_dir"], "-m", "5", "-r", "1", "-t", "ext4"]

    if options.get("volume_label"):
        mkfs_command = [mke2fs_cmd, "-L", options["volume_label"]] + mkfs_command_base[1:] + [options["output_image"], options["size"]]
    else:
        mkfs_command = mkfs_command_base + [options["output_image"], options["size"]]

    print(f"Running command: {' '.join(mkfs_command)}")

    try:
        subprocess.run(mkfs_command, check=True)
        print(f"Successfully created ext4 image: {options['output_image']}")
    except subprocess.CalledProcessError as e:
        print(f"Error creating ext4 image: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Create an ext4 image from a directory.")
    parser.add_argument("-o", "--output", default="rootfs.ext4", dest="output_image", help="The output image filename (default: rootfs.ext4)")
    parser.add_argument("-s", "--size", default="20M", help="Size of the image (default: 20M)")
    parser.add_argument("-l", "--label", default="", dest="volume_label", help="Volume label")
    parser.add_argument("-d", "--dir", required=True, dest="source_dir", help="Source directory")
    parser.add_argument("-m", "--mke2fs", dest="mke2fs", help="Path to the mke2fs executable directory")

    args = parser.parse_args()

    if not os.path.isdir(args.source_dir):
        print(f"Error: Source directory '{args.source_dir}' not found or is not a directory.")
        sys.exit(1)

    options = vars(args)
    create_ext4_image(options)

if __name__ == "__main__":
    main()