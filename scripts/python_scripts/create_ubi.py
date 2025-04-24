#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# Creates a UBI image using ubinize with a configuration file.
#

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
        result = subprocess.run([command, '--help'], check=False, capture_output=True)
        return result.returncode == 0
    except FileNotFoundError:
        return False
    except Exception:
        return False

def get_ubinize_version(ubinize_cmd):
    """
    Gets the version of ubinize.

    Args:
        ubinize_cmd (str): Path to the ubinize executable.

    Returns:
        str: The version of ubinize, or None if the version cannot be determined.
    """
    try:
        result_version = subprocess.run([ubinize_cmd, "--version"], capture_output=True, text=True, check=False)
        output = result_version.stdout + result_version.stderr
        match = re.search(r"ubinize\s+(?:\(mtd-utils\)\s+)?version\s+(\d+\.\d+(?:\.\d+)?)", output, re.IGNORECASE)
        if match:
            return match.group(1)

        result_V = subprocess.run([ubinize_cmd, "-V"], capture_output=True, text=True, check=False)
        output_V = result_V.stdout + result_V.stderr
        match_V = re.search(r"ubinize\s+\(mtd-utils\)\s+(\d+\.\d+\.\d+)", output_V, re.IGNORECASE)
        if match_V:
            return match_V.group(1)

        return None
    except Exception:
        return None

def create_ubi_image(options):
    """
    Creates a UBI image using ubinize.

    Args:
        options (dict): A dictionary containing the command line options.
            output_image (str): Path to the output image file.
            config_file (str): Path to the ubinize configuration file.
            peb_size (str): Physical erase block size (e.g., 131072).
            min_io_size (str): Minimum I/O unit size (e.g., 2048).
            sub_page_size (str, optional): Sub-page size. Defaults to None.
            vid_hdr_offset (str, optional): VID header offset. Defaults to None.
            ubinize (str, optional): Path to the ubinize executable directory. Defaults to None.
    """

    ubinize_cmd = None
    specific_ubinize_path = options.get("ubinize")

    if specific_ubinize_path:
        potential_cmd = os.path.join(specific_ubinize_path, "ubinize")
        if check_command_exists(potential_cmd):
            ubinize_cmd = potential_cmd
            print(f"Using '{specific_ubinize_path}/ubinize'")
        else:
            print(f"Warning: ubinize not found at path: {specific_ubinize_path}. Trying system path.")

    if ubinize_cmd is None:
        default_cmd = "ubinize"
        if check_command_exists(default_cmd):
            ubinize_cmd = default_cmd
            print(f"Using system ubinize")
        else:
            error_msg = f"Error: {RED}'ubinize' command not found.{RESET}\n"
            if specific_ubinize_path:
                error_msg += f"  - Check specified path: {specific_ubinize_path}\n"
            error_msg += "  - Check system path: /usr/sbin or /usr/bin or /usr/local/bin\n"
            error_msg += "Please install it, e.g., with: sudo apt-get install mtd-utils "
            error_msg += "or provide a valid path using the -b option."
            print(error_msg)
            sys.exit(1)

    ubinize_version = get_ubinize_version(ubinize_cmd)
    if ubinize_version:
        print(f"ubinize version: {ubinize_version}")
    else:
        print("Could not determine ubinize version.")
        # Optionally add warnings based on version if needed

    ubinize_command = [
        ubinize_cmd,
        "-o", options["output_image"],
        "-p", options["peb_size"],      # Physical erase block size
        "-m", options["min_io_size"],   # Minimum I/O unit size
    ]

    if options.get("sub_page_size"):
        ubinize_command.extend(["-s", options["sub_page_size"]])
    if options.get("vid_hdr_offset"):
         ubinize_command.extend(["-O", options["vid_hdr_offset"]])

    # Add the mandatory config file argument at the end
    ubinize_command.append(options["config_file"])

    print(f"Running command: {' '.join(ubinize_command)}")

    try:
        subprocess.run(ubinize_command, check=True)
        print(f"Successfully created UBI image: {options['output_image']}")
    except subprocess.CalledProcessError as e:
        print(f"Error creating UBI image: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Create a UBI image using ubinize.")
    parser.add_argument("-o", "--output", required=True, dest="output_image", help="The output UBI image filename")
    parser.add_argument("-c", "--cfg", required=True, dest="config_file", help="UBI configuration file")
    parser.add_argument("-p", "--peb-size", required=True, dest="peb_size", help="Physical erase block size in bytes (e.g., 131072)")
    parser.add_argument("-m", "--min-io-size", required=True, dest="min_io_size", help="Minimum I/O unit size in bytes (e.g., 2048)")
    parser.add_argument("-s", "--sub-page-size", dest="sub_page_size", help="Sub-page size in bytes (optional)")
    parser.add_argument("-O", "--vid-hdr-offset", dest="vid_hdr_offset", help="VID header offset (optional)")
    parser.add_argument("-b", "--ubinize", dest="ubinize", help="Path to the ubinize executable directory (optional)")

    args = parser.parse_args()

    if not os.path.isfile(args.config_file):
        print(f"Error: Configuration file '{args.config_file}' not found.")
        sys.exit(1)

    try:
        int(args.peb_size)
        int(args.min_io_size)
        if args.sub_page_size:
            int(args.sub_page_size)
        if args.vid_hdr_offset:
            int(args.vid_hdr_offset)
    except ValueError as e:
        print(f"Error: Invalid numeric value provided for size/offset argument: {e}")
        sys.exit(1)

    options = vars(args)
    create_ubi_image(options)

if __name__ == "__main__":
    main()
