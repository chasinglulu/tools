#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#
# SPDX-License-Identifier: GPL-2.0+
#
# Copyright (C) 2025, Charleye <wangkart@aliyun.com>
#
# Lists all PDF files in a specified directory and its subdirectories.
#

import os
import argparse

def list_pdf_files(directory):
    """
    Lists all PDF files in the specified directory and its subdirectories.
    """
    if not os.path.isdir(directory):
        print(f"Error: Directory '{directory}' does not exist or is not a valid directory.")
        return

    print(f"Scanning for PDF files in: {directory}\n")
    
    pdf_files_list = []
    for root, _, files in os.walk(directory):
        for filename in files:
            if filename.lower().endswith(".pdf"):
                filepath = os.path.join(root, filename)
                pdf_files_list.append(filepath)

    if not pdf_files_list:
        print("No PDF files found in the specified directory.")
        return

    print("Found the following PDF files:")
    for i, pdf_path in enumerate(pdf_files_list, 1):
        print(f"  {i}. {pdf_path}")
    
    print(f"\nTotal PDF files found: {len(pdf_files_list)}")

def main():
    parser = argparse.ArgumentParser(description="Lists all PDF files in a specified directory and its subdirectories.")
    parser.add_argument("-d", "--directory", 
                        required=True, 
                        help="The directory path to scan for PDF files.")
    
    args = parser.parse_args()
    
    list_pdf_files(args.directory)

if __name__ == "__main__":
    main()
