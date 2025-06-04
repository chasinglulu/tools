#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# Creates a SquashFS filesystem image using mksquashfs.
#

import argparse
import subprocess
import sys
import os
import tempfile
import shutil

# ANSI escape codes for colored output
RED = "\033[91m"
GREEN = "\033[92m"
RESET = "\033[0m"

def check_command_exists(command_path):
    """
    Checks if a command exists at the given path or in system PATH.

    Args:
        command_path (str): The command name or full path to check.

    Returns:
        str: The path to the command if found, None otherwise.
    """
    if os.path.isfile(command_path) and os.access(command_path, os.X_OK):
        return command_path
    
    found_path = shutil.which(command_path)
    if found_path:
        return found_path
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
        return None

def create_squashfs_image(options):
    """
    Creates a SquashFS image from a directory using mksquashfs, potentially with fakeroot.

    Args:
        options (dict): A dictionary containing command options.
    """
    mksquashfs_cmd_name = "mksquashfs"
    mksquashfs_cmd_path = None
    specific_mksquashfs_dir = options.get("mksquashfs_path")

    if specific_mksquashfs_dir:
        potential_cmd = os.path.join(specific_mksquashfs_dir, mksquashfs_cmd_name)
        if os.path.isfile(potential_cmd) and os.access(potential_cmd, os.X_OK):
            mksquashfs_cmd_path = potential_cmd
            print(f"Using mksquashfs from specified path: {mksquashfs_cmd_path}")
        else:
            print(f"{RED}Warning: mksquashfs not found at specified path: {potential_cmd}. Trying system path.{RESET}")

    if mksquashfs_cmd_path is None:
        mksquashfs_cmd_path = check_command_exists(mksquashfs_cmd_name)
        if mksquashfs_cmd_path:
            print(f"Using system mksquashfs: {mksquashfs_cmd_path}")
        else:
            error_msg = f"{RED}Error: '{mksquashfs_cmd_name}' command not found.{RESET}\n"
            if specific_mksquashfs_dir:
                error_msg += f"  - Checked specified path: {specific_mksquashfs_dir}\n"
            error_msg += "  - Checked system PATH.\n"
            error_msg += f"Please install it (e.g., sudo apt-get install squashfs-tools) "
            error_msg += "or provide a valid path using the --mksquashfs-path option."
            print(error_msg)
            sys.exit(1)

    fakeroot_cmd = None
    if options.get("use_fakeroot", True): # Default to using fakeroot
        fakeroot_cmd = find_fakeroot()
        if not fakeroot_cmd:
            print(f"{RED}Error: 'fakeroot' command not found in system PATH.{RESET}")
            print("Please install fakeroot (e.g., sudo apt-get install fakeroot) or use --no-fakeroot.")
            sys.exit(1)

    output_dir = os.path.dirname(options["output_image"])
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    # Base mksquashfs command
    # mksquashfs <source1> <source2> ... <destination> [options]
    mksquashfs_command_parts = [
        f'"{mksquashfs_cmd_path}"',
        f'"{options["source_dir"]}"',
        f'"{options["output_image"]}"',
        "-noappend", # Create a new image, don't append if it exists
        "-all-root" # Make all files owned by root, useful when not root or using fakeroot
    ]

    if options.get("compressor"):
        mksquashfs_command_parts.extend(["-comp", options["compressor"]])
    
    if options.get("block_size"):
        mksquashfs_command_parts.extend(["-b", options["block_size"]])

    if options.get("exclude_dirs"):
        for exclude_dir in options["exclude_dirs"].split(','):
            mksquashfs_command_parts.extend(["-e", exclude_dir.strip()])
            
    if options.get("extra_opts"):
        mksquashfs_command_parts.extend(options["extra_opts"].split())


    mksquashfs_command_str = ' '.join(mksquashfs_command_parts)
    
    script_path = None
    final_command_to_run = []

    if fakeroot_cmd:
        try:
            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix=".sh", prefix="fakeroot_squashfs_") as tmp_script:
                script_path = tmp_script.name
                tmp_script.write("#!/bin/bash\n")
                tmp_script.write("set -e\n")
                # chown is generally not needed if mksquashfs -all-root is used within fakeroot,
                # but can be kept if specific pre-chown is desired.
                # tmp_script.write(f"chown -h -R 0:0 \"{options['source_dir']}\"\n") 
                tmp_script.write("echo 'Running mksquashfs within fakeroot ...'\n")
                tmp_script.write(mksquashfs_command_str + "\n")
                tmp_script.write("echo 'mksquashfs finished.'\n")

            os.chmod(script_path, 0o755)
            
            fakeroot_env = os.environ.copy()
            # FAKEROOTDONTTRYCHOWN might be useful if chown inside script causes issues
            # fakeroot_env['FAKEROOTDONTTRYCHOWN'] = '1' 

            final_command_to_run = [fakeroot_cmd, "--", script_path]
            print(f"Executing with fakeroot: {' '.join(final_command_to_run)}")

        except Exception as e:
            print(f"{RED}Error preparing fakeroot script: {e}{RESET}")
            if script_path and os.path.exists(script_path):
                os.remove(script_path)
            sys.exit(1)
    else:
        # If not using fakeroot, split the command string properly for subprocess.run
        # This is a simplified split; for complex commands, shlex.split might be better.
        final_command_to_run = mksquashfs_command_str.split() 
        # Correctly handle quoted paths if not using shell=True
        # For simplicity, we'll rely on the script for fakeroot, or direct execution for no-fakeroot
        # If running mksquashfs_command_str directly without fakeroot script, it should be:
        # final_command_to_run = [mksquashfs_cmd_path, options["source_dir"], options["output_image"], ...]
        # Rebuilding for direct execution:
        final_command_to_run = [
            mksquashfs_cmd_path,
            options["source_dir"],
            options["output_image"],
            "-noappend",
            "-all-root" # Recommended even without fakeroot if consistent root ownership is desired
        ]
        if options.get("compressor"):
            final_command_to_run.extend(["-comp", options["compressor"]])
        if options.get("block_size"):
            final_command_to_run.extend(["-b", options["block_size"]])
        if options.get("exclude_dirs"):
            for exclude_dir in options["exclude_dirs"].split(','):
                final_command_to_run.extend(["-e", exclude_dir.strip()])
        if options.get("extra_opts"):
            final_command_to_run.extend(options["extra_opts"].split())
        
        print(f"Executing directly: {' '.join(final_command_to_run)}")


    try:
        process_env = os.environ.copy()
        if fakeroot_cmd:
            # process_env['FAKEROOTDONTTRYCHOWN'] = '1' # If needed
            pass

        subprocess.run(final_command_to_run, check=True, env=process_env)
        print(f"{GREEN}Successfully created SquashFS image: {options['output_image']}{RESET}")

    except subprocess.CalledProcessError as e:
        print(f"{RED}Error executing mksquashfs command: {e}{RESET}")
        if script_path and os.path.exists(script_path) and fakeroot_cmd:
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
        if script_path and os.path.exists(script_path) and fakeroot_cmd:
            os.remove(script_path)

def main():
    parser = argparse.ArgumentParser(
        description="Create a SquashFS image from a directory, optionally using fakeroot.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("-o", "--output", required=True, dest="output_image",
                        help="The output SquashFS image filename.")
    parser.add_argument("-d", "--dir", required=True, dest="source_dir",
                        help="Source directory to be squashed.")
    parser.add_argument("--mksquashfs-path", dest="mksquashfs_path",
                        help="Path to the directory containing mksquashfs executable.")
    parser.add_argument("-comp", "--compressor",
                        help="Select compressor. E.g., gzip, lzo, lzma, xz, zstd.")
    parser.add_argument("-b", "--block-size", dest="block_size",
                        help="Set data block to <size> bytes. E.g., 4K, 128K, 1M.")
    parser.add_argument("-e", "--exclude-dirs", dest="exclude_dirs",
                        help="Comma-separated list of directories to exclude.")
    parser.add_argument("--extra-opts", dest="extra_opts", default="",
                        help="String of additional options to pass to mksquashfs.")
    parser.add_argument("--no-fakeroot", action="store_false", dest="use_fakeroot",
                        help="Do not use fakeroot. mksquashfs will run with current user privileges.")


    args = parser.parse_args()

    if not os.path.isdir(args.source_dir):
        print(f"{RED}Error: Source directory '{args.source_dir}' not found or is not a directory.{RESET}")
        sys.exit(1)

    args.source_dir = os.path.abspath(args.source_dir)
    args.output_image = os.path.abspath(args.output_image)
    if args.mksquashfs_path and not os.path.isabs(args.mksquashfs_path) and '/' in args.mksquashfs_path:
         args.mksquashfs_path = os.path.abspath(args.mksquashfs_path)

    options = vars(args)
    create_squashfs_image(options)

if __name__ == "__main__":
    main()
