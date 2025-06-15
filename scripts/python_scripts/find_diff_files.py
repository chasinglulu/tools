#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# Lists files present in a source directory but not in a reference directory.
#

import os
import argparse
from collections import defaultdict

def get_relative_file_paths(directory_path):
    """
    Collects all relative file paths within a given directory.
    Args:
        directory_path (str): The path to the directory.
    Returns:
        set: A set of relative file paths.
    """
    relative_paths = set()
    for root, _, files in os.walk(directory_path):
        for filename in files:
            relative_path = os.path.relpath(os.path.join(root, filename), directory_path)
            relative_paths.add(relative_path)
    return relative_paths

def compare_directories(source_dir_path, reference_dir_path, show_common=False, debug=False):
    """
    Finds and prints files that are in source_dir_path but not in reference_dir_path,
    based on their filenames.
    """
    if not os.path.isdir(source_dir_path):
        print(f"Error: Source directory '{source_dir_path}' does not exist or is not a valid directory.")
        return
    if not os.path.isdir(reference_dir_path):
        print(f"Error: Reference directory '{reference_dir_path}' does not exist or is not a valid directory.")
        return

    print(f"Comparing directories:")
    print(f"  Source directory: {source_dir_path}")
    print(f"  Reference directory: {reference_dir_path}\n")

    files_in_source = get_relative_file_paths(source_dir_path)
    files_in_reference = get_relative_file_paths(reference_dir_path)

    if debug:
        print("\n--- Debug: Files in Source (Relative Paths) ---")
        for r_path in sorted(list(files_in_source)):
            print(f"  - {r_path}")
        print("--- End Debug: Files in Source (Relative Paths) ---\n")

    # Extract filenames from the paths
    filenames_in_source = {os.path.basename(path) for path in files_in_source}
    filenames_in_reference = {os.path.basename(path) for path in files_in_reference}

    unique_to_source = filenames_in_source - filenames_in_reference
    
    if show_common:
        common_files = filenames_in_source.intersection(filenames_in_reference)
    else:
        common_files = set()

    if not unique_to_source and not common_files:
        print(f"No files found in '{os.path.basename(source_dir_path.rstrip('/'))}' that are not also in '{os.path.basename(reference_dir_path.rstrip('/'))}' (based on filenames).")
    else:
        print(f"Files present in '{os.path.basename(source_dir_path.rstrip('/'))}' but not in '{os.path.basename(reference_dir_path.rstrip('/'))}':")
        
        # Collect all full relative paths of unique files in source
        unique_full_paths_in_source = []
        for filename_basename in sorted(list(unique_to_source)):
            # Find the full relative path for the filename in source
            full_relative_path = next((path for path in files_in_source if os.path.basename(path) == filename_basename), None)
            if full_relative_path:
                unique_full_paths_in_source.append(full_relative_path)
            else:
                # Should not happen if logic is correct, but as a fallback
                unique_full_paths_in_source.append(filename_basename + " (Path not found)")

        # Print each unique file with its full relative path, sorted
        for full_path in sorted(unique_full_paths_in_source):
            print(f"  - {full_path}")


        if show_common:
            print("\nCommon files (present in both directories):")
            for filename in sorted(list(common_files)):
                # Find the full path for the filename in source
                full_path_source = next((path for path in files_in_source if os.path.basename(path) == filename), None)
                full_path_reference = next((path for path in files_in_reference if os.path.basename(path) == filename), None)
                if full_path_source and full_path_reference:
                    print(f"  - Source: {full_path_source}")
                    print(f"    Reference: {full_path_reference}")
                else:
                    print(f"  - {filename} (Path not found)")
        
        print(f"\nTotal unique files in Source directory: {len(unique_to_source)}")
        if show_common:
            print(f"Total common files: {len(common_files)}")


def main():
    parser = argparse.ArgumentParser(
        description="Finds files in a source directory that are not present in a reference directory (based on relative file paths)."
    )
    parser.add_argument("-s", "--source-dir",
                        required=True,
                        dest="source_dir",
                        help="Path to the source directory (files from here will be checked).")
    parser.add_argument("-r", "--reference-dir",
                        required=True,
                        dest="reference_dir",
                        help="Path to the reference directory (used for comparison).")
    parser.add_argument("-c", "--show-common",
                        action="store_true",
                        dest="show_common",
                        help="Show common files in the output.")
    parser.add_argument("-D", "--debug",
                        action="store_true",
                        help="Enable debug mode to print intermediate information.")
    
    args = parser.parse_args()
    
    compare_directories(args.source_dir, args.reference_dir, args.show_common, args.debug)

if __name__ == "__main__":
    main()
