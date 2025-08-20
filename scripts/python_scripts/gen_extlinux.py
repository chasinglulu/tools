#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0+
#
# This script generates an extlinux.conf file for booting a Linux kernel.
# It takes various command-line arguments to customize the boot configuration,
# such as kernel path, initrd path, FDT path, label, and menu title.
#
# Copyright (C) 2025 chasinglulu <wangkart@aliyun.com>
#

import argparse

def generate_extlinux_conf(config_data):
    """Generates the extlinux.conf file content."""
    kernel_path = config_data['kernel_path']
    initrd_path = config_data.get('initrd_path')
    label = config_data['label']
    fdt_path = config_data.get('fdt_path')
    menu_title = config_data['menu_title']
    prompt = config_data.get('prompt', 0)

    config = f"""## extlinux/extlinux.conf
##

default {label}
menu title {menu_title}
prompt {prompt}
timeout 0

label {label}
    kernel {kernel_path}
"""
    if initrd_path:
        config += f"""    initrd {initrd_path}"""
    if fdt_path:
        config += f"""    fdt {fdt_path}"""
    config += "\n"
    return config

def write_extlinux_conf(config, output_path):
    """Writes the configuration to the specified output path."""
    with open(output_path, 'w') as f:
        f.write(config)

def main():
    """Main function to generate and write the extlinux.conf file."""
    parser = argparse.ArgumentParser(description="Generate extlinux.conf file.")
    parser.add_argument("-p", "--path", default="/", help="Path prefix for kernel, initrd, and fdt.")
    parser.add_argument("-k", "--kernel", required=False, default="kernel.img", help="Kernel image name.")
    parser.add_argument("-i", "--initrd", help="Initrd image name (optional).")
    parser.add_argument("-o", "--output", default="extlinux.conf", help="Path to the output file (default: extlinux.conf).")
    parser.add_argument("-l", "--label", default="m57_base", help="Label for the entry (default: m57_base).")
    parser.add_argument("-f", "--fdt", help="FDT image name (optional).")
    parser.add_argument("-m", "--menu-title", dest="menu_title", default="Axera Boot Options", help="Menu title (default: Axera Boot Options).")
    parser.add_argument("-r", "--prompt", type=int, default=0, help="Prompt parameter for extlinux.conf (default: 0).")

    args = parser.parse_args()

    kernel_path = args.path + args.kernel
    initrd_path = args.path + args.initrd if args.initrd else None
    fdt_path = args.path + args.fdt if args.fdt else None

    config_data = {
        'kernel_path': kernel_path,
        'initrd_path': initrd_path,
        'label': args.label,
        'fdt_path': fdt_path,
        'menu_title': args.menu_title,
        'prompt': args.prompt
    }

    config = generate_extlinux_conf(config_data)
    write_extlinux_conf(config, args.output)
    print(f"{args.output} generated successfully.")

if __name__ == "__main__":
    main()
