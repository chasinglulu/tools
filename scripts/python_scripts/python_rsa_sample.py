#!/usr/bin/env python3

# Attributeerror _rsaobj object has no 'export key' attribute
# It seems you have Pycrypto, not Pycryptodome. If that is the case,
# exportKey should work, but it's best to uninstall and install Pycryptodome.
#
# sudo pip install Pycryptodome
# API doc
# https://pycryptodome.readthedocs.io/en/latest/src/api.html

import sys
from Crypto.PublicKey import RSA
# from Crypto.PublicKey import RSA
from Crypto.Cipher import PKCS1_OAEP
from base64 import b64decode,b64encode


# 生成 DER 格式的私钥
# mykey = RSA.generate(2048)
# with open("myprivatekey.der", "wb") as f:
#	data = mykey.export_key("DER")
#	f.write(data)

# if len(sys.argv) == 1:
# 	sys.exit("No Public Key files available")

# print("Public Key Filename:", sys.argv[1])
# pkfile = sys.argv[1]

# with open(pkfile, "rb") as f:
# 	binPubKey = f.read()
# 	# key = RSA.importKey(f.read())
# 	# print('e = %d' % key.e)
# 	# print('n = %d' % key.n)

key = RSA.generate(2048)

binPrivKey = key.exportKey('DER')
binPubKey = key.publickey().exportKey('DER')

# print("type = ", type(binPubKey))

# print("binPrivKey = ", binPrivKey)
# print("binPubKey = ", binPubKey)

print("binPubKey hex formate = ", binPubKey.hex())
print("binPubKey int formate = ", int.from_bytes(binPubKey, "little"))

privKeyObj = RSA.import_key(binPrivKey)
pubKeyObj = RSA.import_key(binPubKey)

# print("privKeyObj =", privKeyObj)
print("pubKeyObj = ", pubKeyObj)

strPubKey = pubKeyObj.export_key("PEM")

print("type of strPubKey = ", type(strPubKey))
print("strPubKey bytes =", strPubKey)
print("strPubKey string =", strPubKey.decode("utf-8"))

msg = "attack at dawn"
cipher = PKCS1_OAEP.new(pubKeyObj)
cipher_text = cipher.encrypt(msg.encode())
# emsg = pubKeyObj.encrypt(msg, 'x')[0]

cipher1 = PKCS1_OAEP.new(privKeyObj)
dmsg = cipher1.decrypt(cipher_text)
# dmsg = privKeyObj.decrypt(emsg)
print(dmsg.decode())
print(msg)

assert(msg == dmsg.decode())