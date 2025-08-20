#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
#
# Creates a sparse image from a raw image file using img2simg.
#
# Copyright (C) 2025 chasinglulu <wangkart@aliyun.com>
#

import argparse
import subprocess
import sys
import os
import shutil

# ANSI escape codes for colored output
RED = "\033[91m"
RESET = "\033[0m"

def check_command_exists(command):
    """
    Checks if a command exists and is executable.

    Args:
        command (str): The command to check.

    Returns:
        bool: True if the command exists and is executable, False otherwise.
    """
    try:
        # Try running --help to check if executable
        subprocess.run([command, '--help'], check=False, capture_output=True)
        return True
    except FileNotFoundError:
        return False
    except Exception:
        return False

def create_sparse_image(options):
    """
    Converts a raw image to a sparse image using img2simg.

    Args:
        options (dict): A dictionary containing the following keys:
            input_image (str): Path to the input raw image file.
            output_image (str): Path to the output sparse image file.
            img2simg (str, optional): Path to the img2simg executable directory.
    """
    img2simg_cmd = None
    specific_img2simg_path = options.get("img2simg")

    if specific_img2simg_path:
        potential_cmd = os.path.join(specific_img2simg_path, "img2simg")
        if check_command_exists(potential_cmd):
            img2simg_cmd = potential_cmd
            print(f"Using '{potential_cmd}'")
        else:
            print(f"Warning: img2simg not found or not executable at path: {specific_img2simg_path}. Trying system path.")

    if img2simg_cmd is None:
        default_cmd = "img2simg"
        if check_command_exists(default_cmd):
            img2simg_cmd = default_cmd
            print(f"Using system img2simg: {img2simg_cmd}")

    if not img2simg_cmd:
        error_msg = f"Error: {RED}'img2simg' command not found or not executable.{RESET}\n"
        if specific_img2simg_path:
            error_msg += f"  - Check specified path: {specific_img2simg_path}\n"
        error_msg += "  - Check system path: /usr/bin or /usr/local/bin\n"
        error_msg += "  - Please install img2simg (e.g., sudo apt-get install android-sdk-libsparse-utils)."
        print(error_msg)
        sys.exit(1)

    print(f"Using img2simg: {img2simg_cmd}")

    output_dir = os.path.dirname(options["output_image"])
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    command = [
        img2simg_cmd,
        options["input_image"],
        options["output_image"]
    ]

    print(f"Running command: {' '.join(command)}")

    try:
        subprocess.run(command, check=True, capture_output=True, text=True)
        print(f"Successfully created sparse image: {options['output_image']}")
    except subprocess.CalledProcessError as e:
        print(f"{RED}Error creating sparse image: {e}{RESET}")
        print(f"--- stdout ---\n{e.stdout}")
        print(f"--- stderr ---\n{e.stderr}")
        sys.exit(1)
    except Exception as e:
        print(f"{RED}An unexpected error occurred: {e}{RESET}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Convert a raw image to a sparse image using img2simg.")
    parser.add_argument("-i", "--input", required=True, dest="input_image", help="The input raw image file")
    parser.add_argument("-o", "--output", required=True, dest="output_image", help="The output sparse image file")
    parser.add_argument("-m", "--img2simg", dest="img2simg", help="Path to the img2simg executable directory")

    args = parser.parse_args()

    if not os.path.isfile(args.input_image):
        print(f"Error: Input file '{args.input_image}' not found or is not a file.")
        sys.exit(1)

    args.input_image = os.path.abspath(args.input_image)
    args.output_image = os.path.abspath(args.output_image)

    if args.img2simg and not os.path.isabs(args.img2simg) and '/' in args.img2simg:
        args.img2simg = os.path.abspath(args.img2simg)

    options = vars(args)
    create_sparse_image(options)

if __name__ == "__main__":
    main()
