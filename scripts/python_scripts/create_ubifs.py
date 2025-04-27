#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# Creates a UBIFS filesystem image using mkfs.ubifs.
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

def find_fakeroot():
    """
    Finds the system fakeroot executable.
    """
    # Prefer system fakeroot
    system_fakeroot = shutil.which("fakeroot")
    if system_fakeroot:
        print(f"Using system fakeroot: {system_fakeroot}")
        return system_fakeroot
    else:
        # If system fakeroot is not found, return None.
        # The calling function will handle the error.
        return None

def create_ubifs_image(options):
    """
    Creates a UBIFS image from a directory using fakeroot.

    Args:
        options (dict): A dictionary containing the following keys:
            output_image (str): Path to the output image file.
            source_dir (str): Path to the source directory.
            min_io_size (str): Minimum I/O unit size (e.g., 2048).
            leb_size (str): Logical erase block size (e.g., 126976).
            max_leb_count (str): Maximum logical erase block count.
            mkfs_ubifs (str, optional): Path to the mkfs.ubifs executable directory. Defaults to None.
    """

    mkfs_ubifs_cmd = None
    specific_mkfs_ubifs_path = options.get("mkfs_ubifs")

    if specific_mkfs_ubifs_path:
        potential_cmd = os.path.join(specific_mkfs_ubifs_path, "mkfs.ubifs")
        if check_command_exists(potential_cmd):
            mkfs_ubifs_cmd = potential_cmd
            print(f"Using '{specific_mkfs_ubifs_path}/mkfs.ubifs'")
        else:
            print(f"Warning: mkfs.ubifs not found at path: {specific_mkfs_ubifs_path}. Trying system path.")

    if mkfs_ubifs_cmd is None:
        default_cmd = "mkfs.ubifs"
        if check_command_exists(default_cmd):
            mkfs_ubifs_cmd = default_cmd
            print(f"Using system mkfs.ubifs")
        else:
            error_msg = f"Error: {RED}'mkfs.ubifs' command not found.{RESET}\n"
            if specific_mkfs_ubifs_path:
                error_msg += f"  - Check specified path: {specific_mkfs_ubifs_path}\n"
            error_msg += "  - Check system path: /usr/sbin or /usr/bin or /usr/local/bin\n"
            error_msg += "Please install it, e.g., with: sudo apt-get install mtd-utils "
            error_msg += "or provide a valid path using the -u option."
            print(error_msg)
            sys.exit(1)

    mkfs_ubifs_version = get_mkfs_ubifs_version(mkfs_ubifs_cmd)
    if mkfs_ubifs_version:
        print(f"mkfs.ubifs version: {mkfs_ubifs_version}")
    else:
        print("Could not determine mkfs.ubifs version.")
        # Optionally add warnings based on version if needed

    fakeroot_cmd = find_fakeroot()
    if not fakeroot_cmd:
        print(f"Error: {RED}'fakeroot' command not found in system PATH.{RESET}")
        print("Please install fakeroot (e.g., sudo apt-get install fakeroot).")
        sys.exit(1)

    output_dir = os.path.dirname(options["output_image"])
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    try:
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix=".sh", prefix="fakeroot_ubifs_") as tmp_script:
            script_path = tmp_script.name
            tmp_script.write("#!/bin/bash\n")
            tmp_script.write("set -e\n")
            tmp_script.write(f"chown -h -R 0:0 \"{options['source_dir']}\"\n")
            tmp_script.write("echo 'Running mkfs.ubifs within fakeroot ...'\n")

            # Construct the mkfs.ubifs command parts safely for the script
            mkfs_command_parts = [
                f'"{mkfs_ubifs_cmd}"',
                "-r", f'"{options["source_dir"]}"',
                "-o", f'"{options["output_image"]}"',
                "-m", f'"{options["min_io_size"]}"',
                "-e", f'"{options["leb_size"]}"',
                "-c", f'"{options["max_leb_count"]}"',
            ]
            tmp_script.write(' '.join(mkfs_command_parts) + "\n")
            tmp_script.write("echo 'mkfs.ubifs finished.'\n")

        os.chmod(script_path, 0o755)

        print(f"Executing fakeroot script: {script_path}")
        fakeroot_env = os.environ.copy()
        fakeroot_env['FAKEROOTDONTTRYCHOWN'] = '1'

        fakeroot_process_cmd = [fakeroot_cmd, "--", script_path]
        print(f"Running command: {' '.join(fakeroot_process_cmd)}")
        subprocess.run(fakeroot_process_cmd, check=True, env=fakeroot_env)

        print(f"Successfully created UBIFS image: {options['output_image']}")

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
        if 'script_path' in locals() and os.path.exists(script_path):
            os.remove(script_path)

def main():
    parser = argparse.ArgumentParser(description="Create a UBIFS image from a directory using fakeroot.")
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

    args.source_dir = os.path.abspath(args.source_dir)
    args.output_image = os.path.abspath(args.output_image)
    if args.mkfs_ubifs and not os.path.isabs(args.mkfs_ubifs) and '/' in args.mkfs_ubifs:
         args.mkfs_ubifs = os.path.abspath(args.mkfs_ubifs)

    options = vars(args)
    create_ubifs_image(options)

if __name__ == "__main__":
    main()
