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

def find_duplicate_pdfs(directory, md5sum=False, file_extensions=None):
    """
    Finds files with the same name or same MD5 hash in the specified directory.
    """
    if not os.path.isdir(directory):
        print(f"Error: Directory '{directory}' does not exist or is not a valid directory.")
        return

    print(f"Scanning directory: {directory}\n")

    files_by_name = defaultdict(list)
    files_by_md5 = defaultdict(list)
    files_found = 0

    if file_extensions is None:
        file_extensions = ['.pdf']  # Default to PDF if no extensions are specified
    
    file_extensions = [ext.lower() for ext in file_extensions]

    for root, _, files in os.walk(directory):
        for filename in files:
            if any(filename.lower().endswith(ext) for ext in file_extensions):
                filepath = os.path.join(root, filename)
                files_found += 1
                
                # Group by filename
                files_by_name[filename].append(filepath)
                
                # Group by MD5 hash
                if md5sum:
                    md5_hash = calculate_md5(filepath)
                    if md5_hash:
                        files_by_md5[md5_hash].append(filepath)

    if files_found == 0:
        print("No files found with the specified extensions in the specified directory.")
        return

    print("--- Finding duplicates by filename ---")
    found_duplicates_by_name = False
    for filename, paths in files_by_name.items():
        if len(paths) > 1:
            found_duplicates_by_name = True
            print(f"\nFiles with the same name '{filename}':")
            for path in paths:
                print(f"  - {path}")
    
    if not found_duplicates_by_name:
        print("No files with the same name found.")

    if md5sum:
        print("\n--- Finding duplicates by MD5 hash ---")
        found_duplicates_by_md5 = False
        for md5, paths in files_by_md5.items():
            if len(paths) > 1:
                found_duplicates_by_md5 = True
                print(f"\nFiles with the same MD5 hash (MD5: {md5}):")
                for path in paths:
                    print(f"  - {path}")
        
        if not found_duplicates_by_md5:
            print("No files with the same content (same MD5 hash) found.")

def main():
    parser = argparse.ArgumentParser(description="Finds files with the same name or same MD5 hash in the specified directory.")
    parser.add_argument("-d", "--directory", 
                        required=True, 
                        help="The directory path to scan.")
    
    parser.add_argument("-m", "--md5sum", 
                        action="store_true", 
                        dest="md5sum",
                        default=False,
                        help="Enable comparison by MD5 hash.")
    
    parser.add_argument("-e", "--extensions", 
                        nargs='+',  # Allows multiple extensions to be specified
                        default=['.pdf'],
                        help="Specify the file extensions to search for (e.g., .pdf .txt). Defaults to .pdf")
    
    args = parser.parse_args()
    
    find_duplicate_pdfs(args.directory, args.md5sum, [ext.lower() for ext in args.extensions])

if __name__ == "__main__":
    main()
