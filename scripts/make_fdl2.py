#!/usr/bin/env python3

import sys
import optparse

p = optparse.OptionParser()

p.add_option("-o", action="store", type="string", dest="outfile")
p.add_option("--output", action="store", type="string", dest="outfile")

p.add_option("-s", action="store", type="int", dest="sizeof_header", help="size of SPL header")
p.add_option("--size", action="store", type="int", dest="sizeof_header", help="size of SPL header")

p.add_option("-e", action="store", type="int", dest="offset", help="offset from SPL start address")
p.add_option("--offset", action="store", type="int", dest="offset", help="offset from SPL start address")

p.add_option("-v", action="store_true", dest="verbose")
p.add_option("--verbose", action="store_true", dest="verbose")

p.set_defaults(sizeof_header=0x600, offset=0x40000, verbose=False)

(opts, args) = p.parse_args()

outfile = opts.outfile
sizeof_header = opts.sizeof_header
offset = opts.offset
verbose = opts.verbose

if verbose:
	print("Inputfile list: %s" % ' '.join(args))

if len(args) != 2:
	sys.stderr.write("Uage : python3 %s -o outfile inputfile1 inputfile2\n" % sys.argv[0])
	raise SystemExit(1)

if verbose:
	print("Size of header: 0x%X\n        Offset: 0x%x" % (sizeof_header, offset))

infile1 = open(args[0], "rb")
data1 = infile1.read()
infile2 = open(args[1], "rb")
data2 = infile2.read()
f = open(outfile, "wb+")

f.write(data1)
f.seek(sizeof_header + offset, 0)
f.write(data2)

infile1.close()
infile2.close()
f.close()

if verbose:
	print("Writing of %s finished" % outfile)
