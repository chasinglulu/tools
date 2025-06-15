#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# Scans a directory for duplicate files by filename or MD5 hash.
#

import os
import argparse
import hashlib
from collections import defaultdict

def calculate_md5(filepath, chunk_size=8192):
    """Calculates the MD5 hash of a file."""
    hash_md5 = hashlib.md5()
    try:
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(chunk_size), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()
    except IOError:
        print(f"Error: Could not read file {filepath}")
        return None

def find_duplicate_files(directory, file_extensions=None, scan_all_files=False, exclude_dirs=None):
    """
    Finds files with the same name or same MD5 hash in the specified directory.
    Can scan for specific extensions, all files, or files with no extension.
    Skips specified subdirectories.
    """
    abs_directory = os.path.abspath(directory)
    if not os.path.isdir(abs_directory):
        print(f"Error: Directory '{directory}' does not exist or is not a valid directory.")
        return

    print(f"Scanning directory: {abs_directory}")
    if exclude_dirs:
        print(f"Excluding relative directory paths: {', '.join(exclude_dirs)}")
    print("")

    files_by_name = defaultdict(list)
    files_found = 0

    # exclude_dirs is now expected to be a list of lowercased, stripped strings from main.
    # The following check is fine for robustness if called from elsewhere,
    # but main ensures exclude_dirs is a list.
    if exclude_dirs is None:
        exclude_dirs = []

    for root, dirs, files in os.walk(abs_directory, topdown=True):
        # Modify dirs in-place to exclude specified directories from os.walk
        # Compare normalized relative paths in lowercase

        dirs_to_keep = []
        for d_name in dirs:
            current_dir_full_path = os.path.join(root, d_name)
            current_dir_rel_path = os.path.relpath(current_dir_full_path, abs_directory)
            normalized_rel_path = os.path.normpath(current_dir_rel_path).lower()

            if normalized_rel_path not in exclude_dirs:
                dirs_to_keep.append(d_name)
        dirs[:] = dirs_to_keep

        for filename in files:
            process_this_file = False
            if scan_all_files:
                process_this_file = True
            else:
                # file_extensions should be a list of lowercase strings, including "" for no extension
                if file_extensions:
                    file_name_lower = filename.lower()
                    for ext_filter in file_extensions:
                        if ext_filter == "":
                            if not os.path.splitext(file_name_lower)[1]:
                                process_this_file = True
                                break
                        elif file_name_lower.endswith(ext_filter):
                            process_this_file = True
                            break

            if process_this_file:
                filepath = os.path.join(root, filename)
                files_found += 1

                # Group by filename
                files_by_name[filename].append(filepath)

    if files_found == 0:
        if scan_all_files:
            print("No files found in the specified directory.")
        else:
            print(f"No files found matching the criteria (extensions: {file_extensions}) in the specified directory.")
        return

    print("--- Finding duplicates by filename and content (MD5) ---")
    found_duplicates_by_name_and_content = False
    for filename, paths in files_by_name.items():
        if len(paths) > 1:
            hashes_for_this_name = defaultdict(list)
            for path in paths:
                md5_hash = calculate_md5(path)
                if md5_hash:
                    hashes_for_this_name[md5_hash].append(path)

            for md5_val, md5_paths in hashes_for_this_name.items():
                if len(md5_paths) > 1:
                    found_duplicates_by_name_and_content = True
                    print(f"\nFiles with the same name '{filename}' and same content (MD5: {md5_val}):")
                    for path in md5_paths:
                        print(f"  - {path}")

    if not found_duplicates_by_name_and_content:
        print("No files found with both the same name and same content (MD5).")

def main():
    parser = argparse.ArgumentParser(description="Finds files with the same name or same MD5 hash in the specified directory.")
    parser.add_argument("-d", "--directory", 
                        required=True, 
                        help="The directory path to scan.")

    parser.add_argument("-e", "--extensions", 
                        nargs='+',
                        default=['.pdf'],
                        help="Specify the file extensions to search for (e.g., .pdf .txt). "
                             "Use \"\" (an empty string, may require quoting in shell like -e \"\") for files with no extension. "
                             "Defaults to .pdf. This option is effectively ignored if --all-files is used.")

    parser.add_argument("-a", "--all-files",
                        action="store_true",
                        default=False,
                        help="Scan all files in the directory, regardless of extension. "
                             "If specified, the --extensions option is ignored for filtering purposes.")

    parser.add_argument("-x", "--exclude-dirs",
                        nargs='+',
                        default=[],
                        help="Specify subdirectory paths (relative to the scan directory) "
                             "to exclude. Paths can be separated by spaces, or by commas "
                             "within a single argument (e.g., -x path1 path2 or -x path1,path2 "
                             "or -x \"path1, path with space\"). Example: "
                             "-x venv build .git \"test data/ignore\" or "
                             "-x venv,build,.git,\"test data/ignore\"")

    args = parser.parse_args()

    # Process extensions: convert to lowercase
    processed_extensions = [ext.lower() for ext in args.extensions]

    # Process exclude_dirs:
    # 1. Split items in args.exclude_dirs by comma, in case user provided comma-separated paths in one arg.
    # 2. Flatten the list.
    # 3. Strip whitespace, normalize path, and convert to lowercase for each path.
    raw_excluded_paths = []
    for item in args.exclude_dirs:
        raw_excluded_paths.extend(sub_item.strip() for sub_item in item.split(','))

    processed_exclude_dirs = [os.path.normpath(d).lower() for d in raw_excluded_paths if d]

    find_duplicate_files(args.directory,
                         processed_extensions,
                         args.all_files,
                         processed_exclude_dirs)

if __name__ == "__main__":
    main()
