#!/usr/bin/env python3

import os
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend
import sys

key_bytes = 16
block_size = 16
pad = "\0"


def encrypt(plaintext, key):
    assert len(key) == key_bytes

    # Init
    backend = default_backend()

    # Choose a random, 16-byte IV.
    iv = os.urandom(block_size)

    # Create AES-CBC cipher encryptor
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=backend)
    encryptor = cipher.encryptor()

    # Padding
    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(plaintext) + padder.finalize()

    # Encrypt
    ciphertext = encryptor.update(padded_data) + encryptor.finalize()

    # Return IV and ciphertext.
    return iv + ciphertext

assert len(sys.argv) == 4

f = open(sys.argv[1], "rb")
data = f.read()
f.close()

f = open(sys.argv[2], "rb")
key = f.read()
f.close()

en_data = encrypt(data, key)

f = open(sys.argv[3], "wb")
f.write(en_data)
f.close()
