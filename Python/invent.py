#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Gets test file from ftp.hp.com"""

from DupMerge import DupMerge
from Logger import Logger
from Config import Config
import os
import re

def __main__():
    logger = Logger()
    logger.set_debug_level('info')

    config= Config()
    u_base_path = config.base_path

    dupmerge = DupMerge(
        config.md5_db_path,  u_base_path,
        {'logger': logger},
    )

    re_ignore = [
        re.compile(_)
            for _ in [
                '^' + u_base_path + '/dbs',
                '^' + u_base_path + '/lost\+found',
                '^' + config.ftp_log_path,
                '^' + u_base_path + '/scripts',
                '^' + u_base_path + '/temp',
                '^' + u_base_path + '/txt',
                '^' + u_base_path + '/semaphores',
                '\.tmp$',
                '\.tmp\.\d+$',
                '\.db$'
            ]
    ]

    for root, dirs, files in os.walk(u_base_path):
        full_path = lambda u_name: os.path.join(root, u_name)
        if len(dirs) == 0 and len(files) == 0:
            logger.warning("Removing empty dir '" + root + "'...")
            os.removedirs(root);
            continue;
        dirs.sort()
        files.sort()
        for u_dir in dirs:
            if [ _ for _ in re_ignore if _.search(full_path(u_dir))]:
                dirs.remove(u_dir)
        logger.info("Scanning '" + root + "'...")
        for u_file in files:
            if [ _ for _ in re_ignore if _.search(full_path(u_file))]:
                continue
            dupmerge.file_exists(full_path(u_file))

    logger.info("Doing reverse scan...")

    for u_file in [ _ for _ in dupmerge.all_files() if not os.path.isfile(_)]:
        dupmerge.file_exists(u_file)

__main__()
