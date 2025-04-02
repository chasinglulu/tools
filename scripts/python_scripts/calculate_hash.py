#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# This script calculates the hash of specified input files
# and writes the results to an output file.
# It supports SHA1, SHA256, and SHA512 algorithms.
#
#

import hashlib
import os
import argparse

def calculate_hash(filepath, hash_algorithm="sha1"):
    """Calculates the hash of a file using the specified algorithm."""
    try:
        hash_func = getattr(hashlib, hash_algorithm)
    except AttributeError:
        print(f"Error: Hash algorithm '{hash_algorithm}' not supported.")
        return None

    hash_obj = hash_func()
    try:
        with open(filepath, "rb") as f:
            while chunk := f.read(8192):
                hash_obj.update(chunk)
        return hash_obj.hexdigest()
    except FileNotFoundError:
        return None

def main():
    parser = argparse.ArgumentParser(description="Calculate hash of input files and write to output file.")
    parser.add_argument("-i", "--input_files", nargs="+", help="List of input files to process")
    parser.add_argument("-o", "--output_file", default="sha1sum.txt", help="Output file to write hash results")
    parser.add_argument("-sha", "--hash_algo", default="sha1", choices=["sha1", "sha256", "sha512"], help="Hash algorithm to use: sha1, sha256, or sha512 (default: sha1)")
    args = parser.parse_args()

    if args.output_file == "sha1sum.txt":
        if args.hash_algo == "sha256":
            args.output_file = "sha256sum.txt"
        elif args.hash_algo == "sha512":
            args.output_file = "sha512sum.txt"

    for filepath in args.input_files:
        if not os.path.exists(filepath):
            print(f"Error: File not found: {filepath}")
            return

    try:
        with open(args.output_file, "w") as outfile:
            for filepath in args.input_files:
                hash_value = calculate_hash(filepath, args.hash_algo)
                if hash_value:
                    filename = os.path.basename(filepath)
                    outfile.write(f"{hash_value} {filename}\n")
        print(f"Successfully wrote hash values to {args.output_file}")
    except Exception as e:
        print(f"Error: An error occurred during hash calculation: {e}")

if __name__ == "__main__":
    main()