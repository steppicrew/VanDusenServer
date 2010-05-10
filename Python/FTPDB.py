#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Moddule to handle ftp db queries"""

from DBBase import DBBase
import os
from MD5 import calc_md5

class FTPDB(DBBase):
    """Class to handle ftp db queries"""
    def _init_db(self):
        """initialize db (in case it is not)"""
        self._db_update('''
            CREATE TABLE IF NOT EXISTS ftpfiles (
                path TEXT NOT NULL,
                name TEXT NOT NULL,
                size INTEGER NOT NULL,
                date INTEGER NOT NULL,
                lastseen DATE NOT NULL,
                current INTEGER NOT NULL,
                md5 TEXT
        )''')
        self._db_update('''
            CREATE INDEX IF NOT EXISTS ftp_path_name
            ON ftpfiles ( path, name )
        ''')
        self._db_update('''
            CREATE INDEX IF NOT EXISTS ftp_path_current
            ON ftpfiles ( current, path )
        ''')

    def get_last_date(self,  p_file):
        """checks if file exists in ftp table"""
        t_file = self.parse_file_param(p_file)
        for row in self._db_select(
            "SELECT date FROM ftpfiles WHERE path=? AND name=?",  t_file
        ):
            return int(row[0])
        return None

    def insert_file(self,  p_file,  size,  date,  s_md5= None):
        """inserts file into ftp table"""
        t_file = self.parse_file_param(p_file)
        if s_md5 == None:
            s_md5 = calc_md5(self.local_file_name(t_file))
        self.remove_file(t_file)
        if self._db_update(
            "INSERT INTO ftpfiles ("
                "path, name, size, date, md5, current, lastseen"
            ") "
            "VALUES (?, ?, ?, ?, ?, 2, DATETIME('NOW'))",
            t_file+ (size,  date,  s_md5)
        ).rowcount:
            return s_md5
        return None

    def remove_file(self,  p_file):
        """removes file from ftp table"""
        t_file = self.parse_file_param(p_file)
        return self._db_update(
            "DELETE FROM ftpfiles WHERE path=? AND name=?",  t_file
        ).rowcount

    def touch_file(self,  p_file):
        """sets lastssen to current time"""
        t_file = self.parse_file_param(p_file)
        return self._db_update(
            "UPDATE ftpfiles SET lastseen=DATETIME('NOW'), current=2 "
            "WHERE path=? AND name=?",
            t_file
        ).rowcount

    def update_date_file(self,  p_file, i_date):
        """sets date for ftp file"""
        t_file = self.parse_file_param(p_file)
        return self._db_update(
            "UPDATE ftpfiles SET date=? "
            "WHERE path=? AND name=?",
            (i_date,) + t_file
        ).rowcount

    def prepare_files(self,  dirs):
        """resets all ftp files to <unknown> state"""
        # there should be no files with current=1
        # assume them to be there
        self._db_update(
            "UPDATE ftpfiles SET current=2 WHERE current=1"
        )
        for u_dir in dirs:
            self._db_update(
                "UPDATE ftpfiles SET current=1 WHERE current=2 AND path LIKE ?",
                (os.path.join(u_dir, '%'), )
            )

    def finish_files(self,  except_dirs):
        """restets nonpresent files to <not there> state"""
        # set all denied directory contents as if they were there
        for u_dir in except_dirs:
            self._db_update(
                "UPDATE ftpfiles SET current=2 WHERE current=1 AND path LIKE ?",
                (os.path.join(u_dir, '%'), )
            )
        self._db_update(
            "UPDATE ftpfiles SET current=0 WHERE current=1"
        )

    def get_old_files(self):
        """returns list of nonexistant ftp files"""
        return self._db_select(
            "SELECT path, name FROM ftpfiles WHERE current=0"
        )
