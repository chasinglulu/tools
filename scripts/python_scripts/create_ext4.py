#!/usr/bin/env python3

import argparse
import subprocess
import sys
import os

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

def create_ext4_image(output_image, source_dir, size="20M", volume_label=""):
    """
    Creates an ext4 image from a directory.

    Args:
        output_image (str): Path to the output image file.
        source_dir (str): Path to the source directory.
        size (str): Size of the image (default: 20M).
        volume_label (str, optional): Volume label for the image. Defaults to "".
    """

    if not check_command_exists("mke2fs"):
        print("Error: mke2fs command not found.")
        print("Please install it, e.g., with: sudo apt-get install e2fsprogs")
        sys.exit(1)

    mkfs_command = ["mke2fs", "-F", "-N", "0", "-O", "64bit", "-d", source_dir, "-m", "5", "-r", "1", "-t", "ext4", output_image, size]

    if volume_label:
        mkfs_command = ["mke2fs", "-L", volume_label, "-F", "-N", "0", "-O", "64bit", "-d", source_dir, "-m", "5", "-r", "1", "-t", "ext4", output_image, size]

    try:
        subprocess.run(mkfs_command, check=True)
        print(f"Successfully created ext4 image: {output_image}")
    except subprocess.CalledProcessError as e:
        print(f"Error creating ext4 image: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Create an ext4 image from a directory.")
    parser.add_argument("-o", "--output", dest="output", help="The output image filename")
    parser.add_argument("-s", "--size", default="20M", help="Size of the image (default: 20M)")
    parser.add_argument("-l", "--label", default="", help="Volume label")
    parser.add_argument("-d", "--dir", required=True, help="Source directory")

    args = parser.parse_args()

    create_ext4_image(args.output, args.dir, args.size, args.label)

if __name__ == "__main__":
    main()