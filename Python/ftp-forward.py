#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Gets test file from ftp.hp.com"""

from FTPFetch import FTPFetch
from DupMerge import DupMerge
from Logger import Logger
from Config import Config
import os

def __main__():
    config= Config()
    u_base_path = config.base_path

    logger = Logger(config.ftp_log_path)
    logger.set_debug_level('info')

    dupmerge = DupMerge(
        config.md5_db_path,  u_base_path,
        {'logger': logger},
    )

    ftp = FTPFetch(
        host = config.ftp_hostname,
        port = config.ftp_port,
        credentials = config.ftp_credentials,
        params = {
            'dstdir': config.ftp_base_path,
            'db': config.ftp_db_path,
            'ignore': config.ftp_ignore_list,
            'possible_hidden_dirs': config.ftp_possible_hidden_dirs,
            'dupmerge': dupmerge,
            'reverse': 0,
            'old_cleanup': 1,
            'logger': logger,
        }
    )

    iterator = ftp.iterator([
#        u'/download',
        u'/',
    ])

    while iterator():
        pass

    ftp.close()

__main__()
