#!/usr/bin/python
# -*- coding: utf-8 -*-
from HoerdatDB import HoerdatDB
from Hoerdat import Hoerdat
from DupMerge import DupMerge
from Logger import Logger
from Config import Config
import os
import os.path
import sys

DONT_RESCAN_PRESENT = 0

def __main__():
    logger = Logger()
    logger.set_debug_level('info')

    config= Config()
    u_base_path = config.base_path

    hddb = HoerdatDB(config.hoerdat_db_path, {'debug': 0})

    dupmerge = DupMerge(
        config.md5_db_path,  u_base_path,
        {'logger': logger},
    )

    hd = Hoerdat(hddb)

    for file, md5 in dupmerge.all_files_md5():
        if not hd.set_filename(file, md5):
            continue
        if DONT_RESCAN_PRESENT and hd.data['hoerdat'].get_data('hoerdat_id'):
            continue
        print file, hd.data['hoerdat'].get_data('hoerdat_id')
        fetch_result = hd.fetch_data()
        best_match = hd.get_best_match(fetch_result)
        if best_match:
            hd.merge_data(best_match[0], best_match[1])
            hd.update()
            print "Best rank:", best_match[1]
            print "\t", '"' + hd.data['hoerdat'].get_data('title') + '"'
#            print "\n".join(hd.data['hoerdat'].print_data())

__main__()
