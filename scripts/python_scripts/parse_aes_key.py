#!/usr/bin/env python3

# This script parses a hex string from an input file, validates it, and
# writes it as binary data to an output file.
# It also generates and prints a random 16-byte (128-bit) value as the cipher IV.
#
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.

import argparse
import sys
import os

def parse_hex_file(input_file, output_file):
    with open(input_file, 'r') as file:
        hex_string = file.read().strip()

    # Ensure hex_string is a string
    if not isinstance(hex_string, str):
        print("Error: hex_string is not a valid string.")
        sys.exit(1)

    # Remove "0x" prefix if present
    if hex_string.startswith("0x"):
        hex_string = hex_string[2:]

    bin_key = bytes.fromhex(hex_string)

    # Validate hex string
    if len(bin_key) != 32:
        print("Error: bin_key must be 32 bytes long (256 bits).")
        sys.exit(1)

    with open(output_file, 'wb') as file:
        file.write(bin_key)
    print(f"Successfully wrote binary key to {output_file}")

    # Generate a random 16-byte (128-bit) IV
    iv = os.urandom(16)
    print(f"Cipher IV: {iv.hex()}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Parse a hex key string from a file and write it as binary data.')
    parser.add_argument('-i', '--input', type=str, required=True, help='Input file containing hex key string')
    parser.add_argument('-o', '--output', type=str, required=True, help='Output file to write binary key')

    args = parser.parse_args()

    parse_hex_file(args.input, args.output)
