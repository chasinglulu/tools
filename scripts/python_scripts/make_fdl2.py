'''
SPDX-License-Identifier: GPL-2.0+

Description: This script creates a FDL2 file by combining two input files,
             padding the second file with a specified header size and offset.

Copyright (C) 2025 chasinglulu <wangkart@aliyun.com>

'''
#!/usr/bin/env python3

import sys
import optparse
from typing import Tuple

# Constants definition
DEFAULT_SIZEOF_HEADER = 0x600
DEFAULT_OFFSET = 0x40000

def parse_command_line_arguments() -> Tuple[optparse.Values, list]:
    """Parse command line arguments."""
    parser = optparse.OptionParser(usage="Usage: %prog -o outfile inputfile1 inputfile2 [options]")

    parser.add_option("-o", "--output", action="store", type="string", dest="outfile", help="Output file path")
    parser.add_option("-s", "--size", action="store", type="int", dest="sizeof_header", help="SPL header size")
    parser.add_option("-e", "--offset", action="store", type="int", dest="offset", help="SPL start address offset")
    parser.add_option("-v", "--verbose", action="store_true", dest="verbose", help="Enable verbose output")

    parser.set_defaults(sizeof_header=DEFAULT_SIZEOF_HEADER, offset=DEFAULT_OFFSET, verbose=False)

    return parser.parse_args()


def validate_options(opts: optparse.Values) -> None:
    """Validate command line arguments."""
    if not isinstance(opts.sizeof_header, int) or opts.sizeof_header < 0:
        raise ValueError("sizeof_header must be a positive integer")
    if not isinstance(opts.offset, int) or opts.offset < 0:
        raise ValueError("offset must be a non-negative integer")


def create_fdl2(outfile: str, sizeof_header: int, offset: int, infile1: str, infile2: str) -> None:
    """Create FDL2 file."""
    try:
        with open(infile1, "rb") as f1:
            data1 = f1.read()
        with open(infile2, "rb") as f2:
            data2 = f2.read()

        with open(outfile, "wb+") as outfile_obj:
            outfile_obj.write(data1)
            outfile_obj.seek(sizeof_header + offset, 0)
            outfile_obj.write(data2)

        print("Writing of %s finished" % outfile)

    except FileNotFoundError as e:
        print(f"File not found: {e}")
        raise
    except IOError as e:
        print(f"IO error: {e}")
        raise


def main() -> None:
    """Main function."""
    opts, args = parse_command_line_arguments()

    if len(args) != 2:
        print("Usage: python3 %s -o outfile inputfile1 inputfile2" % sys.argv[0])
        sys.exit(1)

    try:
        validate_options(opts)
        if opts.verbose:
            print("Inputfile list: %s" % ' '.join(args))
            print("Size of header: 0x%X, Offset: 0x%x" % (opts.sizeof_header, opts.offset))

        create_fdl2(opts.outfile, opts.sizeof_header, opts.offset, args[0], args[1])

    except ValueError as e:
        print(f"Parameter error: {e}")
        sys.exit(1)
    except Exception as e:
        print("An unexpected error occurred")
        sys.exit(1)


if __name__ == "__main__":
    main()
