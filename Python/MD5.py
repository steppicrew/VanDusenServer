#!/usr/bin/python
# -*- coding: utf-8 -*-
"""calculates md5 checksum"""

import hashlib

MD5_BLOCKSIZE = 1024 * 100

def calc_md5(u_file):
    """calculate md5 hash of the given file"""
    md5hash = hashlib.md5()

    def read_file(fd_file):
        """anonymous function to read the file in blocks"""
        data = fd_file.read(MD5_BLOCKSIZE)
        if data == '':
            return 0
        md5hash.update(data)
        return 1

    try:
        fd_file = open(u_file,  'rb')
        while read_file(fd_file):
            pass
    finally:
        fd_file.close()

    return md5hash.hexdigest()

