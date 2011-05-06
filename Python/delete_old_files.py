#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Gets test file from ftp.hp.com"""

from FTPFetch import FTPFetch
from DupMerge import DupMerge
from Logger import Logger
from Config import Config
import os

def __main__():
    logger = Logger()
    logger.set_debug_level('info')

    config= Config()

    u_base_path = config.base_path

    dupmerge = DupMerge(
        config.md5_db_path,  u_base_path,
        {'logger': logger},
    )

    ftp = FTPFetch(
        host = config.ftp_hostname,
        credentials = config.ftp_credentials,
        params = {
            'dstdir': config.ftp_base_path,
            'db': config.ftp_db_path,
            'dupmerge': dupmerge,
            'logger': logger,
        }
    )

    ftp.cleanup_old_ftp_files(delete=1)

__main__()
