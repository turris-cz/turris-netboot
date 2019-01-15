#!/usr/bin/env python

from Crypto.Cipher import AES
from Crypto.Util import Counter
from Crypto import Random
import sys

key_bytes = 16
block_size = 16
pad = '\0'

def encrypt(plaintext, key):
    assert len(key) == key_bytes

    # Choose a random, 16-byte IV.
    iv = Random.new().read(AES.block_size)

    # Create AES-CBC cipher.
    aes = AES.new(key, AES.MODE_CBC, iv)

    # Padding
    to_pad_len = len(plaintext) % block_size
    if to_pad_len > 0:
       pad_string = pad * (16 - to_pad_len)
       plaintext = plaintext + pad_string

    # Encrypt and return IV and ciphertext.
    ciphertext = aes.encrypt(plaintext)
    return iv + ciphertext

assert len(sys.argv) == 4

f = open(sys.argv[1], 'rb')
data = f.read()
f.close()

f = open(sys.argv[2], 'rb')
key = f.read()
f.close()

en_data = encrypt(data,key)

f = open(sys.argv[3], 'w')
f.write(en_data)
f.close()
