#!/usr/bin/python
# -*- coding: utf-8 -*-
"""searches for duplicate title entries in hoerdat.db"""
from DBBase import DBBase
from Config import Config

config= Config()

db = DBBase(config.hoerdat_db_path)

def get_all_duplicates():
    """returns list of all duplicate md5 sums"""
    return [(_[0], _[1]) for _ in db._db_select(
        "SELECT play_id, title FROM titles GROUP BY play_id, title HAVING (COUNT(*) > 1)"
    )]

def get_main_title(play_id):
    for title in db._db_select(
        "SELECT title_id FROM plays WHERE _id = ?", (play_id,)
    ):
        return title[0]
    return None
    
def get_titles(play_id, title, main_title_id):
#    db._db_update(
#        "DELETE FROM titles WHERE play_id=? AND title=? AND _id!=?", (play_id, title, main_title_id)
#    )
#    return
    for title in db._db_select(
        "SELECT * FROM titles WHERE play_id=? AND title=? AND _id!=?", (play_id, title, main_title_id)
    ):
        print title

for play_id, title in get_all_duplicates():
    main_title_id = get_main_title(play_id)
    get_titles(play_id, title, main_title_id)
