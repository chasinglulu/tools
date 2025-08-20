#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# Creates an ext4 filesystem image using mke2fs.
#

import argparse
import subprocess
import sys
import os
import re
import tempfile
import shutil

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

def find_fakeroot():
    """
    Finds the system fakeroot executable.
    """
    system_fakeroot = shutil.which("fakeroot")
    if system_fakeroot:
        print(f"Using system fakeroot: {system_fakeroot}")
        return system_fakeroot
    else:
        # If system fakeroot is not found, return None.
        # The calling function will handle the error.
        return None

def create_ext4_image(options):
    """
    Creates an ext4 image from a directory using fakeroot.

    Args:
        options (dict): A dictionary containing the following keys:
            output_image (str): Path to the output image file.
            source_dir (str): Path to the source directory.
            size (str): Size of the image (default: 20M).
            volume_label (str, optional): Volume label for the image. Defaults to "".
            mke2fs (str, optional): Path to the mke2fs executable directory. Defaults to None.
            selinux_context (str, optional): Path to the Selinux context file.
            minimal (bool, optional): Use minimal mkfs parameters. Defaults to False.
    """

    mke2fs_cmd = None
    specific_mke2fs_path = options.get("mke2fs")
    selinux_context_path = options.get("selinux_context")

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

    fakeroot_cmd = find_fakeroot()
    if not fakeroot_cmd:
        print(f"Error: {RED}'fakeroot' command not found in system PATH.{RESET}")
        print("Please install fakeroot (e.g., sudo apt-get install fakeroot).")
        sys.exit(1)

    output_dir = os.path.dirname(options["output_image"])
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    if options.get("minimal", False):
        mkfs_command_parts = [
            f'"{mke2fs_cmd}"', "-F",
            "-N", "0",
            "-O", "^has_journal",
            "-b", "4096",
            "-d", f'"{options["source_dir"]}"',
            "-m", "0",
            "-r", "1",
            "-t", "ext4",
            "-T", "small",
            "-E", "lazy_itable_init=0,lazy_journal_init=0"
        ]
    else:
        mkfs_command_parts = [
            f'"{mke2fs_cmd}"', "-F", "-N", "0", "-O", "64bit",
            "-d", f'"{options["source_dir"]}"',
            "-m", "5", "-r", "1", "-t", "ext4"
        ]

    if options.get("volume_label"):
        mkfs_command_parts += ["-L", f'"{options["volume_label"]}"']

    # Append output image and size at the end
    size_str = str(options["size"])
    if not re.search(r'[KMG]$', size_str, re.IGNORECASE):
        size_str += "K"
    mkfs_command_parts += [f'"{options["output_image"]}"', f'"{size_str}"']

    mkfs_command_str = ' '.join(mkfs_command_parts)

    script_path = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix=".sh", prefix="fakeroot_ext4_") as tmp_script:
            script_path = tmp_script.name
            tmp_script.write("#!/bin/bash\n")
            tmp_script.write("set -e\n")
            # Ensure correct ownership within fakeroot environment
            tmp_script.write(f"chown -h -R 0:0 \"{options['source_dir']}\"\n")
            tmp_script.write("echo 'Running mke2fs within fakeroot ...'\n")
            if selinux_context_path:
                tmp_script.write(f"setfiles -r {options['source_dir']} {selinux_context_path} {options['source_dir']}\n")
            tmp_script.write(mkfs_command_str + "\n")
            tmp_script.write("echo 'mke2fs finished.'\n")

        os.chmod(script_path, 0o755)

        print(f"Executing fakeroot script: {script_path}")
        fakeroot_env = os.environ.copy()
        fakeroot_env['FAKEROOTDONTTRYCHOWN'] = '1'

        fakeroot_process_cmd = [fakeroot_cmd, "--", script_path]
        print(f"Running command: {' '.join(fakeroot_process_cmd)}")
        subprocess.run(fakeroot_process_cmd, check=True, env=fakeroot_env)

        print(f"Successfully created ext4 image: {options['output_image']}")

    except subprocess.CalledProcessError as e:
        print(f"{RED}Error executing fakeroot script: {e}{RESET}")
        # Print script content for debugging
        if script_path and os.path.exists(script_path):
            try:
                with open(script_path, 'r') as f:
                    print("--- Fakeroot Script Content ---")
                    print(f.read())
                    print("-----------------------------")
            except Exception as read_err:
                print(f"Could not read script content: {read_err}")
        sys.exit(1)
    except Exception as e:
        print(f"{RED}An unexpected error occurred: {e}{RESET}")
        sys.exit(1)
    finally:
        if script_path and os.path.exists(script_path):
            os.remove(script_path)

def get_dir_size_bytes(path):
    """
    Get the actual disk usage of a directory (in bytes).
    """
    try:
        result = subprocess.run(['du', '-sb', path], capture_output=True, text=True, check=True)
        size_str = result.stdout.split()[0]
        return int(size_str)
    except Exception as e:
        print(f"Failed to get directory size: {e}")
        sys.exit(1)

def try_create_ext4_image(options, size_str):
    """
    Try to create an ext4 image with the specified size, return True if success.
    """
    options = options.copy()
    options["size"] = size_str
    try:
        create_ext4_image(options)
        return True
    except SystemExit as e:
        return False

def auto_calc_min_ext4_size(options):
    """
    Automatically calculate the minimal ext4 image size and create the image.
    """
    dir_size = get_dir_size_bytes(options["source_dir"])
    print(f"Actual disk usage of source directory: {dir_size} bytes")
    # Start from actual size, increase by 1MB each time
    min_size = dir_size
    step = 512 * 1024
    max_try = 40
    for i in range(max_try):
        size_bytes = min_size + i * step
        size_str = f"{size_bytes // 1024}K"
        print(f"Trying image size: {size_str}")
        try:
            create_ext4_image({**options, "size": size_str, "minimal": True})
            print(f"Found minimal usable ext4 image size: {size_str}")
            return
        except SystemExit:
            continue
    print("Failed to find a suitable minimal ext4 image size, please check the source directory or parameters.")
    sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Create an ext4 image from a directory using fakeroot.")
    parser.add_argument("-o", "--output", default="rootfs.ext4", dest="output_image", help="The output image filename (default: rootfs.ext4)")
    parser.add_argument("-s", "--size", default="20M", help="Size of the image (default: 20M)")
    parser.add_argument("-l", "--label", default="", dest="volume_label", help="Volume label")
    parser.add_argument("-d", "--dir", required=True, dest="source_dir", help="Source directory")
    parser.add_argument("-m", "--mke2fs", dest="mke2fs", help="Path to the mke2fs executable directory")
    parser.add_argument("-e", "--selinux", dest="selinux_context", help="Path to the Selinux context file")
    parser.add_argument(
        "-a", "--auto-min-size",
        action="store_true",
        help="Automatically calculate and use minimal ext4 image size"
    )
    parser.add_argument(
        "-M", "--minimal",
        action="store_true",
        help="Use minimal mkfs parameters (for smallest image, normally used with --auto-min-size)"
    )

    args = parser.parse_args()

    if not os.path.isdir(args.source_dir):
        print(f"Error: Source directory '{args.source_dir}' not found or is not a directory.")
        sys.exit(1)

    args.source_dir = os.path.abspath(args.source_dir)
    args.output_image = os.path.abspath(args.output_image)
    if args.mke2fs and not os.path.isabs(args.mke2fs) and '/' in args.mke2fs:
         args.mke2fs = os.path.abspath(args.mke2fs)

    options = vars(args)
    if args.auto_min_size:
        auto_calc_min_ext4_size(options)
    else:
        create_ext4_image(options)

if __name__ == "__main__":
    main()