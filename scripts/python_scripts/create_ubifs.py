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
        # Use shell=True might be needed if command is not directly in PATH
        # but typically checking without shell is safer.
        subprocess.run([command, '--help'], check=False, capture_output=True)
        # mkfs.ubifs returns 1 on --help, check stderr for usage info
        # A simple check for FileNotFoundError is often sufficient
        return True
    except FileNotFoundError:
        return False
    except Exception:
        # Catch other potential exceptions during the check
        return False

def get_mkfs_ubifs_version(mkfs_ubifs_cmd):
    """
    Gets the version of mkfs.ubifs.

    Args:
        mkfs_ubifs_cmd (str): Path to the mkfs.ubifs executable.

    Returns:
        str: The version of mkfs.ubifs, or None if the version cannot be determined.
    """
    try:
        # mkfs.ubifs usually prints version info to stderr with -V
        result = subprocess.run([mkfs_ubifs_cmd, "-V"], capture_output=True, text=True, check=False)
        output = result.stderr # Or result.stdout, depending on the specific version/distribution
        # Adjust regex based on actual mkfs.ubifs -V output format
        match = re.search(r"mkfs.ubifs\s+.*?(\d+\.\d+)", output)
        if match:
            return match.group(1)
        # Fallback check if version is in stdout
        output = result.stdout
        match = re.search(r"mkfs.ubifs\s+.*?(\d+\.\d+)", output)
        if match:
            return match.group(1)
        return None
    except Exception:
        return None

def create_ubifs_image(options):
    """
    Creates a UBIFS image from a directory.

    Args:
        options (dict): A dictionary containing the following keys:
            output_image (str): Path to the output image file.
            source_dir (str): Path to the source directory.
            min_io_size (str): Minimum I/O unit size (e.g., 2048).
            leb_size (str): Logical erase block size (e.g., 126976).
            max_leb_count (str): Maximum logical erase block count.
            mkfs_ubifs (str, optional): Path to the mkfs.ubifs executable directory. Defaults to None.
    """

    mkfs_ubifs_cmd = os.path.join(options.get("mkfs_ubifs", ""), "mkfs.ubifs") if options.get("mkfs_ubifs") else "mkfs.ubifs"

    if not check_command_exists(mkfs_ubifs_cmd):
        if options.get("mkfs_ubifs"):
            print(f"Error: {mkfs_ubifs_cmd} command not found.")
            print(f"Please provide the correct path. Example: {os.path.dirname(options['mkfs_ubifs'])}/mkfs.ubifs")
        else:
            print(f"Error: {mkfs_ubifs_cmd} command not found.")
            print("Please install it, e.g., with: sudo apt-get install mtd-utils")
        sys.exit(1)

    mkfs_ubifs_version = get_mkfs_ubifs_version(mkfs_ubifs_cmd)
    if mkfs_ubifs_version:
        print(f"mkfs.ubifs version: {mkfs_ubifs_version}")
    else:
        print("Could not determine mkfs.ubifs version.")
        # Optionally add warnings based on version if needed

    # Construct the mkfs.ubifs command using options dictionary
    mkfs_command = [
        mkfs_ubifs_cmd,
        "-r", options["source_dir"],
        "-o", options["output_image"],
        "-m", options["min_io_size"],
        "-e", options["leb_size"],
        "-c", options["max_leb_count"],
    ]

    print(f"Running command: {' '.join(mkfs_command)}")

    try:
        subprocess.run(mkfs_command, check=True)
        print(f"Successfully created UBIFS image: {options['output_image']}")
    except subprocess.CalledProcessError as e:
        print(f"Error creating UBIFS image: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Create a UBIFS image from a directory.")
    parser.add_argument("-o", "--output", required=True, dest="output_image", help="The output image filename")
    parser.add_argument("-d", "--dir", required=True, dest="source_dir", help="Source directory")
    parser.add_argument("-m", "--min-io-size", required=True, dest="min_io_size", help="Minimum I/O unit size (e.g., 2048)")
    parser.add_argument("-e", "--leb-size", required=True, dest="leb_size", help="Logical erase block size (e.g., 126976)")
    parser.add_argument("-c", "--max-leb-count", required=True, dest="max_leb_count", help="Maximum logical erase block count")
    parser.add_argument("-u", "--mkfs-ubifs", dest="mkfs_ubifs", help="Path to the mkfs.ubifs executable directory")

    args = parser.parse_args()

    # Ensure source directory exists
    if not os.path.isdir(args.source_dir):
        print(f"Error: Source directory '{args.source_dir}' not found or is not a directory.")
        sys.exit(1)

    options = vars(args)
    create_ubifs_image(options)

if __name__ == "__main__":
    main()
