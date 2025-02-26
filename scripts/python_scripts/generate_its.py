#!/usr/bin/env python3

# This script generates Image Tree Source (ITS) files for various firmware components.
# It takes paths to firmware images (bl31, uboot, tee, kernel, dtb, rootfs, extlinux.conf)
# as input and generates corresponding .its files that can be used with the mkimage tool
# to create bootable images.
#
# Copyright (C) 2025 Charleye <wangkart@aliyun.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.

import argparse
import os
import subprocess
import gzip
import lz4.frame
import bz2
import sys

def write_its(output_file, content):
    """
    Generates an ITS file with the given content.

    Args:
        output_file (str): The path to the output ITS file.
        content (str): The content of the ITS file.
    """
    with open(output_file, 'w') as f:
        f.write(content)
    print(f"Successfully generated ITS file: {output_file}")

def create_image_node(kwargs):
    """
    Generates the image node content for an ITS file.

    Args:
        kwargs (dict): A dictionary containing the arguments.

    Returns:
        str: The image node content.
    """
    image_node = f"""
        {kwargs.get('node_name', 'firmware-1')} {{
            data = /incbin/("{kwargs['data_path']}");
            description = "{kwargs['description']}";
            type = "{kwargs['image_type']}";
            arch = "{kwargs['arch']}";
            compression = "{kwargs.get('compression', 'none')}";
            load = <{kwargs['load_addr']}>;"""
    if kwargs.get('entry_point'):
        image_node += f"""
            entry = <{kwargs['entry_point']}>;"""
    if kwargs.get('os_name'):
        image_node += f"""
            os = "{kwargs['os_name']}";"""
    if 'kernel-version' in kwargs:
        image_node += f"""
            kernel-version = {kwargs['kernel-version']};"""
    if 'fdt-version' in kwargs:
        image_node += f"""
            fdt-version = {kwargs['fdt-version']};"""
    image_node += f"""
            hash-1 {{
                algo = "{kwargs.get('sha_algo', 'sha256')}";
            }};
        }};
"""
    return image_node

def create_config_node(description, sha_algo="sha256", rsa_algo="rsa2048", config_name="conf-1", is_kernel=False, has_ramdisk=False):
    """
    Generates the configuration node content for an ITS file.

    Args:
        description (str): Description of the configuration.
        sha_algo (str, optional): SHA algorithm. Defaults to "sha256".
        rsa_algo (str, optional): RSA algorithm. Defaults to "rsa2048".
        config_name (str, optional): Name of the configuration node. Defaults to "conf-1".
        is_kernel (bool, optional): Whether the config node is for kernel. Defaults to False.
        has_ramdisk (bool, optional): Whether the config node includes ramdisk. Defaults to False.

    Returns:
        str: The configuration node content.
    """
    signature_algo = f"{sha_algo},{rsa_algo}"
    key_name_hint = f"akcipher{rsa_algo[3:]}"

    config_node = f"""
        default = "{config_name}";
        {config_name} {{
            description = "{description}";"""
    if is_kernel:
        config_node += f"""
            kernel = "kernel";
            fdt = "fdt-1";"""
        if has_ramdisk:
            config_node += f"""
            ramdisk = "ramdisk-1";"""
        sign_images = ["fdt", "kernel"]
        if has_ramdisk:
            sign_images.insert(1, "ramdisk")
        sign_images_str = ", ".join(f'"{img}"' for img in sign_images)

        signature_props = f"""
            signature {{
                sign-images = {sign_images_str};
                algo = "{signature_algo}";
                key-name-hint = "{key_name_hint}";
            }};"""
        config_node += f"""
            {signature_props}
        }};
"""
    else:
        signature_props = f"""
            signature {{
                sign-images = "firmware";
                algo = "{signature_algo}";
                key-name-hint = "{key_name_hint}";
            }};"""
        config_node += f"""
            firmware = "firmware-1";
            loadables = "firmware-1";
            {signature_props}
        }};
"""
    return config_node

def create_its(kwargs, is_kernel=False):
    """
    Generates the content of an ITS file.

    Args:
        kwargs (dict): A dictionary containing the arguments.
        is_kernel (bool, optional): Whether the ITS file is for kernel. Defaults to False.

    Returns:
        str: The content of the ITS file.
    """
    image_node = create_image_node(kwargs)
    config_kwargs = {
        'description': kwargs['description'],
        'sha_algo': kwargs.get('sha_algo', "sha256"),
        'rsa_algo': kwargs.get('rsa_algo', "rsa2048"),
        'is_kernel': is_kernel
    }
    config_node = create_config_node(**config_kwargs)

    content = f"""
/dts-v1/;
/ {{
    description = "{kwargs['description']}";
    #address-cells = <2>;
    images {{{image_node}    }};
    configurations {{{config_node}   }};
}};
"""
    return content

def create_kernel_its(kwargs):
    """
    Generates the content for a kernel ITS file with separate kernel, dtb, and rootfs images.

    Args:
        kwargs (dict): A dictionary containing the arguments.

    Returns:
        str: The content of the kernel ITS file.
    """
    load_addr_str = hex_to_addr_tuple(kwargs['load_addr'])
    entry_point_str = hex_to_addr_tuple(kwargs['entry_point'])

    common_image_props = {
        'arch': "arm64",
        'sha_algo': kwargs['sha_algo'],
        'compression': kwargs['compression']
    }

    kernel_image_props = {
        **kwargs,
        'data_path': kwargs['kernel_path'],
        'description': "Linux kernel image",
        'image_type': "kernel",
        'os_name': "linux",
        'load_addr': load_addr_str,
        'entry_point': entry_point_str,
        'node_name': "kernel",
        'kernel-version': "<1>",
        **common_image_props
    }
    kernel_image_node = create_image_node(kernel_image_props)

    has_ramdisk = False
    if kwargs.get('rootfs_path'):
        has_ramdisk = True

    config_node = create_config_node(
        description="Linux kernel with FDT and ramdisk" if has_ramdisk else "Linux kernel with FDT",
        sha_algo=kwargs['sha_algo'],
        rsa_algo=kwargs['rsa_algo'],
        is_kernel=True,
        has_ramdisk=has_ramdisk
    )

    ramdisk_image_node = ""
    if has_ramdisk:
        rootfs_load_addr = kwargs.get('rootfs_load_addr')
        if rootfs_load_addr is None:
            rootfs_load_addr = "0x0"
        rootfs_load_addr = hex_to_addr_tuple(rootfs_load_addr)

        ramdisk_image_props = {
            **kwargs,
            'data_path': kwargs['rootfs_path'],
            'description': "ramdisk image",
            'image_type': "ramdisk",
            'os_name': "linux",
            'load_addr': rootfs_load_addr,
            'node_name': "ramdisk-1",
            **common_image_props
        }
        # Ensure ramdisk_image_props does not have 'entry_point'
        if 'entry_point' in ramdisk_image_props:
            del ramdisk_image_props['entry_point']
        ramdisk_image_node = create_image_node(ramdisk_image_props)

    dtb_load_addr = kwargs.get('dtb_load_addr')
    if dtb_load_addr is None:
        dtb_load_addr = "0x0"
    dtb_load_addr = hex_to_addr_tuple(dtb_load_addr)

    fdt_image_props = {
        **kwargs,
        'data_path': kwargs['dtb_path'],
        'description': "kernel FDT",
        'image_type': "flat_dt",
        'arch': "arm64",
        'load_addr': dtb_load_addr,
        'node_name': "fdt-1",
        'fdt-version': "<1>",
        **common_image_props
    }
    # Ensure fdt_image_props does not have 'entry_point'
    if 'entry_point' in fdt_image_props:
        del fdt_image_props['entry_point']
    fdt_image_node = create_image_node(fdt_image_props)

    content = f"""
/dts-v1/;
/ {{
    description = "kernel image with one or more FDT blobs";
    #address-cells = <2>;
    images {{{kernel_image_node}{ramdisk_image_node}{fdt_image_node}    }};
    configurations {{{config_node}    }};
}};
"""
    return content

def hex_to_addr_tuple(hex_addr):
    """
    Converts a hexadecimal address to a tuple of two 32-bit hexadecimal numbers.

    Args:
        hex_addr (str): Hexadecimal address string (e.g., "0x100104000").

    Returns:
        str: A string containing two 32-bit hexadecimal numbers (e.g., "0x1 0x00104000").
    """
    if hex_addr is None:
        return None
    if not isinstance(hex_addr, str):
        raise TypeError("hex_addr must be a string")
    addr = int(hex_addr, 16)
    high = (addr >> 32) & 0xFFFFFFFF
    low = addr & 0xFFFFFFFF
    return f"0x{high:x} 0x{low:08x}"

def is_compressed(file_path, comp_type, debug):
    """
    Checks if a file is compressed using the specified compression type.
    Returns True if compressed, False otherwise.
    """
    try:
        if comp_type == "gzip":
            with gzip.open(file_path, 'rb') as f:
                try:
                    f.peek(1)
                    return True
                except OSError as e:
                    if debug:
                        print(f"Debug: gzip.open failed to peek {file_path}. Reason: {e}")
                    return False
        elif comp_type == "lz4":
            try:
                with lz4.frame.open(file_path, 'rb') as f:
                    try:
                        f.read(1)
                        return True
                    except Exception as e: # lz4.frame.LZ4FError doesn't exist in all versions
                        if debug:
                            print(f"Debug: lz4.frame failed to decompress {file_path}. Reason: {e}")
                        # Fallback to using the file command
                        try:
                            result = subprocess.run(['file', file_path], capture_output=True, text=True, check=False)
                            if "LZ4 compressed data" in result.stdout:
                                return True
                            else:
                                if debug:
                                    print(f"Debug: File command indicates {file_path} is not LZ4 compressed.")
                                return False
                        except FileNotFoundError:
                            print(f"Error: 'file' command not found. Please ensure it is installed.")
                            return False
            except FileNotFoundError:
                print(f"File not found: {file_path}")
                return None  # Indicate file not found
            except Exception as e:
                print(f"Error checking lz4 compression for {file_path}: {e}")
                return False
        elif comp_type == "bzip2":
            with bz2.open(file_path, 'rb') as f:
                try:
                    f.read(1)
                    return True
                except OSError as e:
                    if debug:
                        print(f"Debug: bz2.open failed to read {file_path}. Reason: {e}")
                    return False
        else:
            print(f"Unsupported compression type: {comp_type}")
            return False
    except FileNotFoundError:
        print(f"File not found: {file_path}")
        return None  # Indicate file not found
    except (gzip.BadGzipFile, OSError):
        if debug:
            print(f"Debug: {file_path} is not a valid {comp_type} file")
        return False
    except Exception as e:
        print(f"Error checking {comp_type} compression for {file_path}: {e}")
        return False

def check_and_compress(file_path, comp_type, debug=False):
    """
    Checks if a file is compressed. If not, compress it.
    Returns the path to the (potentially new) compressed file.
    """
    if not file_path:
        return None

    # Check if already compressed with another algorithm
    for c_type in ["gzip", "lz4", "bzip2"]:
        if is_compressed(file_path, c_type, debug):
            if c_type == comp_type:
                if debug:
                    print(f"Debug: {file_path} is already {comp_type} compressed")
                return file_path
            else:
                print(f"Error: {file_path} is already compressed with {c_type}, cannot compress with {comp_type}")
                sys.exit(1)

    suffix = {"gzip": ".gz", "lz4": ".lz4", "bzip2": ".bz2"}.get(comp_type)
    if not suffix:
        print(f"Unsupported compression type: {comp_type}")
        return file_path

    compressed_file_path = file_path + suffix
    compress_cmd = {
        "gzip": ['gzip', '-f', '-k', file_path],
        "lz4": ['lz4', '-f', file_path, compressed_file_path],
        "bzip2": ['bzip2', '-f', '-k', file_path]
    }.get(comp_type)

    is_already_compressed = is_compressed(file_path, comp_type, debug)
    if is_already_compressed is None:
        return None

    if is_already_compressed:
        if debug:
            print(f"Debug: {file_path} is already {comp_type} compressed")
        return file_path

    # Create a new compressed file
    try:
        subprocess.run(compress_cmd, check=True)  # -k keeps the original file
        return compressed_file_path
    except subprocess.CalledProcessError as e:
        print(f"Error compressing {file_path}: {e}")
        return None
def main():
    parser = argparse.ArgumentParser(description='Generate ITS files for different firmware components.')
    parser.add_argument('--bl31', type=str, help='Path to ARM Trusted Firmware image')
    parser.add_argument('--uboot', type=str, help='Path to U-Boot image')
    parser.add_argument('--tee', type=str, help='Path to OP-TEE image')
    parser.add_argument('--kernel', type=str, help='Path to Linux Kernel Image')
    parser.add_argument('--dtb', type=str, help='Path to Kernel dtb file')
    parser.add_argument('--rootfs', type=str, help='Path to rootfs image')
    parser.add_argument('--extlinux', type=str, help='Path to extlinux.conf')
    parser.add_argument('--output_dir', type=str, default='.', help='Output directory for ITS files (default: current directory)')
    parser.add_argument('--load_addr', type=str, help='Load address for the image in hex format (e.g., 0x100104000)', default=None)
    parser.add_argument('--entry_point', type=str, help='Entry point for the image in hex format (e.g., 0x100104000)', default=None)
    parser.add_argument('--sha_algo', type=str, help='SHA algorithm (e.g., sha256)', choices=['sha256', 'sha384', 'sha512'], default="sha256")
    parser.add_argument('--rsa_algo', type=str, help='RSA algorithm (e.g., rsa2048)', choices=['rsa2048', 'rsa3072', 'rsa4096'], default="rsa2048")
    parser.add_argument('--comp', type=str, help='Compression type (e.g., none)', choices=['none', 'gzip', 'lz4', 'bzip2'], default="none")
    parser.add_argument('--dtb_load_addr', type=str, help='Load address for the dtb in hex format (e.g., 0x18000000)', default=None)
    parser.add_argument('--rootfs_load_addr', type=str, help='Load address for the rootfs in hex format (e.g., 0x19000000)', default=None)
    parser.add_argument('-d', '--debug', action='store_true', help='Enable debug output', default=False)

    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    # Define default load addresses and entry points for different image types
    default_addresses = {
        'bl31': {'load_addr': "0x100104000", 'entry_point': "0x100104000", 'os_name': "arm-trusted-firmware", 'description': "ARM Trusted Firmware"},
        'uboot': {'load_addr': "0x100200000", 'entry_point': "0x100200000", 'os_name': "u-boot", 'description': "U-Boot"},
        'tee': {'load_addr': "0x104000000", 'entry_point': "0x104000000", 'os_name': "tee", 'description': "Trusted Execution Environment Image"},
        'extlinux': {'load_addr': "0x10FF00000", 'entry_point': None, 'os_name': "linux", 'description': "Linux Boot Configurations"},
        'kernel': {'load_addr': "0x110000000", 'entry_point': "0x110000000"},
        'ramdisk': {'load_addr': "0x119000000", 'entry_point': None},
        'fdt': {'load_addr': "0x118000000", 'entry_point': None}
    }

    img_types = ['bl31', 'uboot', 'tee', 'extlinux']
    for img_type in img_types:
        path = getattr(args, img_type)
        if path:
            if args.comp != 'none':
                path = check_and_compress(path, args.comp, args.debug)

            default_addr = default_addresses[img_type]
            load_addr = args.load_addr if args.load_addr else default_addr['load_addr']
            entry_point = args.entry_point if args.entry_point else default_addr['entry_point']
            load_addr = hex_to_addr_tuple(load_addr)
            entry_point = hex_to_addr_tuple(entry_point)

            its_kwargs = {
                'description': default_addr['description'],
                'data_path': path,
                'image_type': "firmware",
                'arch': "arm64",
                'os_name': default_addr['os_name'],
                'load_addr': load_addr,
                'entry_point': entry_point,
                'sha_algo': args.sha_algo,
                'rsa_algo': args.rsa_algo,
                'compression': args.comp
            }
            content = create_its(its_kwargs)
            write_its(os.path.join(args.output_dir, f'{img_type}.its'), content)

    if args.kernel:
        if not args.dtb:
            parser.error("--kernel requires --dtb")

        default_kernel_addr = default_addresses['kernel']
        default_fdt_addr = default_addresses['fdt']
        default_ramdisk_addr = default_addresses['ramdisk']

        kernel_path = args.kernel
        dtb_path = args.dtb
        rootfs_path = args.rootfs

        if args.comp != 'none':
            kernel_path = check_and_compress(kernel_path, args.comp, args.debug)
            dtb_path = check_and_compress(dtb_path, args.comp, args.debug)
            rootfs_path = check_and_compress(rootfs_path, args.comp, args.debug)

        kernel_kwargs = {
            'kernel_path': kernel_path,
            'dtb_path': dtb_path,
            'rootfs_path': rootfs_path,
            'load_addr': args.load_addr if args.load_addr else default_kernel_addr['load_addr'],
            'entry_point': args.entry_point if args.entry_point else default_kernel_addr['entry_point'],
            'sha_algo': args.sha_algo,
            'rsa_algo': args.rsa_algo,
            'compression': args.comp,
            'dtb_load_addr': args.dtb_load_addr if args.dtb_load_addr else default_addresses['fdt']['load_addr'],
            'rootfs_load_addr': args.rootfs_load_addr if args.rootfs_load_addr else default_addresses['ramdisk']['load_addr'],
        }
        kernel_content = create_kernel_its(kernel_kwargs)
        write_its(os.path.join(args.output_dir, 'kernel.its'), kernel_content)

if __name__ == "__main__":
    main()
