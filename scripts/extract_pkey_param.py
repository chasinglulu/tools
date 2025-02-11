#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2025, Charleye
#
# This script extracts RSA public key parameters from a given file.
# It reads the public key file, extracts the parameters, and prints them.
#
# Usage:
#   python3 extract_pkey_param.py [-k keyfile]
#
# Options:
#   -k, --keyfile      Public key file (default: default_pubkey.pem)
#
# For any questions, please contact: wangkart@aliyun.com

import sys
import argparse
import os
import sympy
from sympy.solvers.diophantine import diop_solve
from Crypto.PublicKey import RSA

def big_endian_words(val):
	"""Converts integer into array of big endian words"""
	# Convert integer to hexadecimal string
	str_val = hex(val)[2:]
	# Split the string into bytes
	bytearr = [str_val[i : i + 2] for i in range(0, len(str_val), 2)]
	# Group bytes into sets of 4 bytes
	sets = [bytearr[i : i + 4] for i in range(0, len(bytearr), 4)]
	# Reverse the bytes in each group (BIG endian)
	# list(map(list.reverse, sets))
	# Join bytes in each group (WORD)
	sets = list(map(''.join, sets))
	# Convert to lower case
	sets = list(map(str.lower, sets))
	# Append '0x' to each word
	sets = list(map('0x'.__add__, sets))

	return sets

def print_big(prop, list, space):
	"""Format and print big endian byte array"""
	arr = [list[i : i + 4] for i in range(0, len(list), 4)]
	print(prop + " = <" + ' '.join(arr[0]))

	for i in range(1, len(arr)):
		if i != len(arr) - 1:
			print(' ' * space + ' '.join(arr[i]))
		else:
			print(' ' * space + ' '.join(arr[i]) + ">;")
	return arr

def extract_pkey_params(keyfile):
	"""Extract and print RSA public key parameters from the given file"""
	if not os.path.isfile(keyfile):
		sys.exit(f"Error: The file '{keyfile}' does not exist or is not a valid file.")

	print("Public Key Filename:", keyfile)

	try:
		with open(keyfile, "rb") as f:
			key = RSA.importKey(f.read())
	except (OSError, ValueError) as e:
		sys.exit(f"Error: Failed to open or read the file '{keyfile}': {e}")

	t1 = int(key.e)
	num_bits = int(len(bin(key.n)) - 2)

	# modulus
	N = big_endian_words(key.n)
	# r-squared
	squared = (2 ** num_bits) ** 2 % key.n
	R = big_endian_words(squared)

	# calculate n0 inverse
	inv, k = sympy.symbols('inv k')
	eq = diop_solve((key.n & 0xFFFFFFFF) * inv - (2 ** 32) * k + 1)
	exp = "( " + str(eq[0]).replace("*t_0", "") + " )"+ " % " + str(int(2 ** 32))
	n0inverse = eval(exp)

	print("\nPublic Key Parameters: \n")
	print_big("rsa,r-squared", R, 17)
	print_big("rsa,modulus", N, 15)
	print("rsa,exponent = <0x%08x 0x%08x>;" % ((t1 >> 32) & 0xFFFFFFFF, t1 & 0xFFFFFFFF))
	print("rsa,num-bits = <0x%08x>;" % num_bits)
	print("rsa,n0-inverse = <" + hex(n0inverse) + ">;")

if __name__ == "__main__":
	# Parse command line arguments
	parser = argparse.ArgumentParser(description="Extract RSA public key parameters.")
	parser.add_argument("-k", "--keyfile", nargs='?', default="default_pubkey.pem", help="Public key file (default: default_pubkey.pem)")
	args = parser.parse_args()

	# Extract and print public key parameters
	extract_pkey_params(args.keyfile)
