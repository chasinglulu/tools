#!/usr/bin/env python3

import sys
# Diophantine equations can be solved using sympy package.
import sympy
from sympy.solvers.diophantine import diop_solve
from Crypto.PublicKey import RSA

def big_endian_words(val):
	"""Converts integer into array of big endian words"""
	# Convert val to hex
	str_val = hex(val)[2:]
	# Split the string into bytes
	bytearr = [str_val[i : i + 2] for i in range(0, len(str_val), 2)]
	# Group bytes into group os 4 bytes
	sets = [bytearr[i : i + 4] for i in range(0, len(bytearr), 4)]
	# Reverse the bytes in each group (BIG endian)
	# list(map(list.reverse, sets))
	# Join bytes in each group (WORD)
	sets = list(map(''.join, sets))
	# Convert to lower case
	sets = list(map(str.lower, sets))
	# Append '0x' to the word
	sets = list(map('0x'.__add__, sets))

	return sets

def print_big(prop, list, space):
	arr = [list[i : i + 4] for i in range(0, len(N), 4)]
	print(prop + " = <" + ' '.join(arr[0]))

	for i in range(1, len(arr)):
		if i != len(arr) - 1:
			print(' ' * space + ' '.join(arr[i]))
		else:
			print(' ' * space + ' '.join(arr[i]) + ">;")
	return arr


if len(sys.argv) == 1:
	sys.exit("No Public Key files available")

print("Public Key Filename:", sys.argv[1])
pkfile = sys.argv[1]

with open(pkfile, "rb") as f:
	key = RSA.importKey(f.read())
	# print('e = %d' % key.e)
	# print('n = %d' % key.n)

t1 = int(key.e)
num_bits = int(len(bin(key.n)) - 2)

# modulus
N = big_endian_words(key.n)
# r-squared
squared = (2 ** num_bits) ** 2 % key.n
R = big_endian_words(squared)

inv, k = sympy.symbols('inv k')
eq = diop_solve((key.n & 0xFFFFFFFF) * inv - (2 ** 32) * k + 1)
exp = "( " + str(eq[0]).replace("*t_0", "") + " )"+ " % " + str(int(2 ** 32))
n0inverse = eval(exp)


print("\nPublic Key Parameter: \n")
print_big("rsa,r-squared", R, 17)
print_big("rsa,modulus", N, 15)
print("rsa,exponent = <0x%08x 0x%08x>;" % ((t1 >> 32) & 0xFFFFFFFF, t1 & 0xFFFFFFFF))
print("rsa,num-bits = <0x%08x>;" % num_bits)
print("rsa,n0-inverse = <" + hex(n0inverse) + ">;")
