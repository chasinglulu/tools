#!/usr/bin/env python3
'''
SPDX-License-Identifier: GPL-2.0+

Description:
    This script parses a YAML file and extracts the page_size and block_size
    from the flash field, and flash_type from the config field. It uses the
    argparse module to accept the YAML file path as a command-line argument.

Copyright (C) 2025 Xinlu Wang <wangxinlu@axera-tech.com>

'''

import yaml
import argparse

def parse_yaml(yaml_file):
    """
    Parse the specified YAML file and extract page_size, block_size from the flash field,
    and flash_type from the config field.
    """
    try:
        with open(yaml_file, 'r') as f:
            data = yaml.safe_load(f)

        if 'config' not in data:
            raise KeyError("config field not found in the YAML file.")
        if 'flash_type' not in data['config']:
            raise KeyError("flash_type not found in the config field.")

        if 'flash' not in data:
            raise KeyError("flash field not found in the YAML file.")

        if 'page_size' not in data['flash'] or 'block_size' not in data['flash']:
            raise KeyError("page_size or block_size not found in the flash field.")

        flash_type = data['config']['flash_type']
        page_size = data['flash']['page_size']
        block_size = data['flash']['block_size']

        print(f"Flash Type: {flash_type.capitalize()}")
        print(f"Page Size: 0x{page_size:X}")
        print(f"Eraseblock Size: 0x{block_size:X}")

    except FileNotFoundError:
        print(f"Error: File not found: {yaml_file}")
    except KeyError as e:
        print(f"Error: {e}")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Parse YAML file to extract flash parameters.")
    parser.add_argument("-f", "--file", dest="yaml_file", help="Path to the YAML file", required=True)
    args = parser.parse_args()

    parse_yaml(args.yaml_file)
