#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Module to handle unique file hashes"""
from MD5 import calc_md5
import os
from DBBase import DBBase

class DupMerge(DBBase):
    """A simple class to track files by MD5 checksum."""
    def _init_db(self):
        """initialize db (in case it is not)"""
        self._db_update('''CREATE TABLE IF NOT EXISTS files (
                path TEXT NOT NULL,
                name TEXT NOT NULL,
                size INTEGER NOT NULL,
                date INTEGER NOT NULL,
                md5 TEXT NOT NULL
        )''')
        self._db_update('''
            CREATE INDEX IF NOT EXISTS file_path_name
            ON files ( path, name )
        ''')
        self._db_update('''
            CREATE INDEX IF NOT EXISTS file_path
            ON files ( path )
        ''')
        self._db_update('''
            CREATE INDEX IF NOT EXISTS file_size
            ON files ( size )
        ''')
        self._db_update('''
            CREATE INDEX IF NOT EXISTS file_md5
            ON files ( md5 )
        ''')

    def file_exists(self,  p_file):
        """checks if file does exist in db and corrects wrong/missing entries"""
        t_file = self.parse_file_param(p_file)
        t_row = None
        for row in self._db_select("SELECT size, date, md5 FROM files WHERE "
            "path=? AND name=?",  t_file):
            t_row = row
            break

        # do some plausibility check
        u_local_file = self.local_file_name(p_file)
        if t_row != None:
            if os.path.isfile(u_local_file):
                i_size = os.path.getsize(u_local_file)
                i_date = int(os.path.getmtime(u_local_file))
                if i_size != t_row[0]:
                    self._logger.warning(
                        "Wrong size of file in DB '" + u_local_file
                        + "' (" + unicode(i_size) + " != " + unicode(t_row[0])
                        + "). Readding."
                    )
                    return self.insert_file(
                        t_file,  size = i_size,  date = i_date
                    )
                if i_date != t_row[1]:
                    self._logger.warning(
                        "Wrong mtime of file in DB '" + u_local_file
                        + "' (" + unicode(i_date) + "!=" + unicode(t_row[1])
                        + "). Readding."
                    )
                    return self.insert_file(
                        t_file,  size= i_size,  date= i_date
                    )
            else:
                self._logger.warning(
                    "File '" + u_local_file + "' is in DB but does not exist."
                    " Removing."
                )
                self.remove_file(t_file)
                return None
        else:
            if os.path.isfile(u_local_file):
                self._logger.warning(
                    "File '" + u_local_file + "' is not in DB"
                    " but does exist. Adding."
                )
                return self.insert_file(t_file)
        return t_row

    def get_files_by_size(self,  i_size):
        """gets all files of given size"""
        for u_file in self._db_select(
            "SELECT path, name FROM files WHERE size=?",
            (i_size, )
        ):
            yield self.local_file_name(u_file)

    def get_files_by_path(self,  u_path):
        """gets all files of given path"""
        for u_file in self._db_select(
            "SELECT name FROM files WHERE path=?",
            (u_path, )
        ):
            yield u_file[0]

    def all_files(self):
        """returns iterator over all files"""
        for u_file in self._db_select(
            "SELECT path, name FROM files"
        ):
            yield self.local_file_name(u_file)

    def all_files_md5(self):
        """returns iterator over all files"""
        for u_file in self._db_select(
            "SELECT path, name, md5 FROM files"
        ):
            yield self.local_file_name((u_file[0], u_file[1])), u_file[2]

    def get_files_by_md5(self,  u_md5):
        """gets all files of given md5"""
        for u_file in self._db_select(
            "SELECT path, name FROM files WHERE md5=? ORDER BY date DESC",
            (u_md5, )
        ):
            yield self.local_file_name(u_file)

    def get_duplicates(self,  p_file,  u_md5= None):
        """gets all duplicates of given file"""
        u_local_file = self.local_file_name(p_file)
        if u_md5 == None:
            u_md5 = self.__get_md5(p_file)
            if u_md5 == None:
                self._logger.error(
                    "Could not get MD5 for '" + u_local_file + "'"
                )
                return
        for u_file in self.get_files_by_md5(u_md5):
            if u_file != u_local_file and self.file_exists(u_file):
                yield u_file

    def __get_md5(self,  p_file):
        """gets md5 of file from db"""
        t_row = self.file_exists(p_file)
        if t_row == None:
            return None
        return t_row[2]

    def insert_file(self,  p_file,  size= None,  date= None,  u_md5= None):
        """inserts a single file"""
        t_file = self.parse_file_param(p_file)
        u_local_file = self.local_file_name(t_file)
        self.remove_file(t_file)
        if size == None:
            size = os.path.getsize(u_local_file)
        if date == None:
            date = int(os.path.getmtime(u_local_file))
        if u_md5 == None:
            u_md5 = calc_md5(u_local_file)
        if self._db_update(
            "INSERT INTO files (path, name, size, date, md5) "
            "VALUES (?, ?, ?, ?, ?)",
            t_file + (size,  date,  u_md5)
        ).rowcount:
            self._logger.info("File '" + u_local_file + "' added.")
            return (size,  date,  u_md5)
        return None

    def update_date_file(self, p_file):
        """updates date for file"""
        t_file = self.parse_file_param(p_file)
        i_date = int(os.path.getmtime(self.local_file_name(t_file)))
        if self._db_update(
            "UPDATE files SET date=? WHERE path=? AND name=?",
            (i_date, ) + t_file
        ).rowcount:
            self._logger.info(
                "Date for file '" + self.local_file_name(t_file)
                + "' updated."
            )

    def remove_file(self,  p_file):
        """removes file from db"""
        t_file = self.parse_file_param(p_file)
        if self._db_update(
            "DELETE FROM files WHERE path=? AND name=?",  t_file
        ).rowcount:
            self._logger.info(
                "File '" + self.local_file_name(t_file) + "' removed."
            )

    def get_all_duplicates(self):
        """returns list of all duplicate md5 sums"""
        return [_[0] for _ in self._db_select(
            "SELECT md5 FROM files GROUP BY md5 HAVING (COUNT(md5) > 1)"
        )]

    def hardlink(self,  u_src,  u_dst):
        """Hard links files"""
        u_tmp_file = u_dst + ".tmp"
        if os.path.isfile(u_tmp_file):
            os.remove(u_tmp_file)
        try:
            self.prepare_file(u_dst)
            if os.path.isfile(u_dst):
                os.rename(u_dst,  u_tmp_file)
            os.link(u_src, u_dst)
            if os.path.isfile(u_tmp_file):
                os.remove(u_tmp_file)
                # if file previously existed, only update date
                self.update_date_file(u_dst)
            else:
                self.insert_file(u_dst)
        except os.error:
            self._logger.error(
                "Hardlinking '" + u_src + "'->'" + u_dst + "' failed."
            )
            if os.path.isfile(u_tmp_file):
                if os.path.isfile(u_dst):
                    os.remove(u_dst)
                os.rename(u_tmp_file,  u_dst)
            raise

    def rename_file(self,  u_src_name,  u_dst_name):
        """Renames a given file, updating md5hash as well"""
        self.prepare_file(u_dst_name)
        self.remove_file(u_src_name)
        os.rename(u_src_name,  u_dst_name)
        self.insert_file(u_dst_name)

    def prepare_file(self, u_file):
        """creates diretories if required"""
        u_dir_name = os.path.dirname(u_file)
        if not os.path.isdir(u_dir_name):
            os.makedirs(u_dir_name)

