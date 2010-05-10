#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Module to handle db queries"""
from Logger import Logger, TO_UNICODE
import sqlite3
import os

DB_TIMEOUT = 30.0

class DBBase(object):
    """Base class for db handling
    dbname: name of database
    basedir: base dir for path parsing
        (will be removed from files before inserting in db and vice versa)
    params['logger']: logger object
    params['debug']: set True for db debug messages (if logger is unset)
    """
    def __init__(self,  dbname,  basedir='./', params=None):
        self.dbname = os.path.realpath(dbname)
        self.basedir = os.path.realpath(basedir)
        if params == None:
            params = {}
        if 'logger' in params and params['logger']:
            self._logger = params['logger']
        else:
            self._logger = Logger()
            if 'debug' in params and params['debug']:
                self._logger.set_debug_level('debug')
        # create dir for db file if it does not exists already
        u_db_dir_name = os.path.dirname(self.dbname)
        if not os.path.isdir(u_db_dir_name):
            os.makedirs(u_db_dir_name)
        self.dbh = sqlite3.connect(self.dbname, timeout = DB_TIMEOUT)
#        self.dbh.text_factory = str
        self.__db_lock = 0
        self._init_db()

    def _init_db(self):
        """dummy function to initialize db"""
        pass

    def _db_update(self,  s_sql,  t_data = ()):
        """does db update and commits changes"""
        t_data= tuple([TO_UNICODE(_) for _ in t_data])
        self._logger.debug(
            "Executing '" + s_sql + "' with data '"
            + "', '".join(t_data) + "'"
        )
        try:
            result = self.dbh.execute(s_sql,  t_data)
            if not self.__db_lock:
                self.dbh.commit()
        except sqlite3.OperationalError:
            self.dbh.rollback()
            self._logger.error(
                "Error executing '" + s_sql + "' with data '"
                + "', '".join(t_data) + "'"
            )
            raise
        return result

    def _db_select(self,  s_sql,  t_data = ()):
        """does db update and commits changes"""
        t_data= tuple([TO_UNICODE(_) for _ in t_data])
        self._logger.debug(
            "Executing '" + s_sql + "' with data '"
            + "', '".join(t_data) + "'"
        )
        result = self.dbh.execute(s_sql,  t_data)
        return result

    def db_begin_transaction(self):
        """begins db transaction"""
        self.__db_lock += 1

    def db_commit(self):
        """commits db transaction"""
        if self.__db_lock:
            self.__db_lock -= 1
        if not self.__db_lock:
            self.dbh.commit()

    def db_rollback(self):
        """rolls back db transaction"""
        if self.__db_lock:
            self.__db_lock -= 1
        self.dbh.rollback()

    def parse_file_param(self,  t_file):
        """returns file parameter as tuple. Strips basdir if needed"""
        if type(t_file).__name__ != 'tuple':
            t_file = os.path.split(t_file)
        if t_file[0].find(self.basedir) == 0:
            t_file = (t_file[0][len(self.basedir):],  t_file[1])
        return (os.path.normpath(t_file[0]) + '/',  t_file[1])

    def local_file_name(self,  p_file):
        """returns real file name on local devices"""
        t_file = self.parse_file_param(p_file)
        return os.path.realpath(
            self.basedir + os.path.join('/' + t_file[0], t_file[1])
        )




