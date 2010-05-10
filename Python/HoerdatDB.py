#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Class to manage HoerdatDB requests"""

from DBObject import DBTable, DBObject, DBObjectError
from DBBase import DBBase

class HoerdatDB(DBBase):
    """Class to manage HoerdatDB requests
    dbname: name of database
    params['logger']: logger object
    params['debug']: set True for db debug messages (if logger is unset)
    """
    def __init__(self, dbname, params=None):
        super(HoerdatDB, self).__init__(dbname, params=params)
        self.__tables = {}
        for u_table in [
            'files', 'plays', 'titles', 'authors',
            'names', 'stations', 'play_station',
            'keywords', 'play_keyword',
            'genres', 'play_genre',
            'roles',
        ]:
            self.__tables[u_table] = DBTable(
                u_table, self, params={'create_table': 1}
            )
        self.__init_tables()
        #init all tables (is not required)
        for u_table in sorted(self.__tables):
            self.__tables[u_table]._init_table()

    def __init_tables(self):
        """build tables with references"""
        # TABLE files
        db = self.__tables['files']
        db._add_mandatory_field('md5', ('TEXT', 'PRIMARY KEY'))
        db._add_mandatory_ref(
            'play_id', self.__tables['plays'], virtual = 'play',
            ref_virtual = 'files',
        )
        db._add_field('file_rank', 'INTEGER')
        db._add_field('part_num', 'INTEGER')
        db._add_field('part_count', 'INTEGER')
        db._add_field('quality', 'INTEGER')

        # TABLE authors
        db = self.__tables['authors']
        db._add_mandatory_field('name', 'TEXT')
        db._add_field('given_name', 'TEXT')

        # TABLE names
        db = self.__tables['names']
        db._add_mandatory_field('name', 'TEXT')

        # TABLE plays
        db = self.__tables['plays']
        db._add_field('hoerdat_id', ('INTEGER', 'UNIQUE'))
        db._add_mandatory_ref(
            'title_id', self.__tables['titles'], virtual = 'title',
        )
        db._add_field('addition', 'TEXT')
        db._add_ref(
            'arranger_id', self.__tables['names'], virtual = 'arranger',
            ref_virtual = 'arranger_of_play',
        )
        db._add_field('audio', 'INTEGER')
        db._add_ref(
            'author_id', self.__tables['authors'], virtual = 'author',
            ref_virtual = 'play',
        )
        db._add_virtual(
            'author_name', 'author_id', self.__tables['authors'], '_id',
            next_field = 'name', single = 1
        )
        db._add_virtual(
            'author_given_name', 'author_id', self.__tables['authors'], '_id',
            next_field = 'given_name', single = 1
        )
        db._add_field('description', 'TEXT')
        db._add_ref(
            'director_id', self.__tables['names'], virtual = 'director',
            ref_virtual = 'director_of_play',
        )
        db._add_field('quality', 'INTEGER')
        db._add_field('year', 'INTEGER')

        # TABLE titles
        db = self.__tables['titles']
        db._add_field('title', 'TEXT')
        db._add_mandatory_ref(
            'play_id', self.__tables['plays'], virtual = 'play',
            ref_virtual = 'all_titles',
        )
        self.__tables['plays']._add_virtual(
            'title_name', 'title_id', db, '_id',
            next_field = 'title', single = 1,
        )

        # TABLE roles
        db = self.__tables['roles']
        db._add_field('role', 'TEXT')
        db._add_mandatory_ref(
            'play_id', self.__tables['plays'], virtual = 'play',
            ref_virtual = 'roles',
        )
        db._add_mandatory_ref(
            'artist_id', self.__tables['names'], virtual = 'artist',
            ref_virtual = 'roles',
        )
        db._add_virtual(
            'artist_name', 'artist_id', self.__tables['names'], '_id',
            next_field = 'name', single = 1
        )
        self.__tables['plays']._add_virtual(
            'artists', '_id', db, 'play_id', next_field = 'artist',
        )
        self.__tables['plays']._add_virtual(
            'artist_names', '_id', db, 'play_id', next_field = 'artist_name',
        )
        self.__tables['names']._add_virtual(
            'artist_in_plays', '_id', db, 'artist_id', next_field = 'play',
        )

        # TABLE stations
        db = self.__tables['stations']
        db._add_mandatory_field('station', 'TEXT')

        # TABLE play_station
        db = self.__tables['play_station']
        db._add_mandatory_ref(
            'play_id', self.__tables['plays'], virtual = 'play',
        )
        db._add_mandatory_ref(
            'station_id', self.__tables['stations'], virtual = 'station',
        )
        self.__tables['plays']._add_virtual(
            'stations', '_id', db, 'play_id', next_field = 'station',
        )
        self.__tables['stations']._add_virtual(
            'plays', '_id', db, 'station_id', next_field = 'play',
        )

        # TABLE genres
        db = self.__tables['genres']
        db._add_mandatory_field('genre', 'TEXT')

        # TABLE play_genre
        db = self.__tables['play_genre']
        db._add_mandatory_ref(
            'play_id', self.__tables['plays'], virtual = 'play',
        )
        db._add_mandatory_ref(
            'genre_id', self.__tables['genres'], virtual = 'genre',
        )
        self.__tables['plays']._add_virtual(
            'genres', '_id', db, 'play_id', next_field = 'genre',
        )
        self.__tables['genres']._add_virtual(
            'plays', '_id', db, 'genre_id', next_field = 'play',
        )

        # TABLE keywords
        db = self.__tables['keywords']
        db._add_mandatory_field('keyword', 'TEXT')

        # TABLE play_keyword
        db = self.__tables['play_keyword']
        db._add_mandatory_ref(
            'play_id', self.__tables['plays'], virtual = 'play',
        )
        db._add_mandatory_ref(
            'keyword_id', self.__tables['keywords'], virtual = 'keyword',
        )
        self.__tables['plays']._add_virtual(
            'keywords', '_id', db, 'play_id', next_field = 'keyword',
        )
        self.__tables['keywords']._add_virtual(
            'plays', '_id', db, 'keyword_id', next_field = 'play',
        )

    def __get_table(self, table):
        """returns table or raises an exception"""
        if not table in self.__tables:
            raise DBObjectError("Table '" + table + "' does not exist!")
        return self.__tables[table]

    def get(self, table, where=None):
        """get specified object(s) from given table"""
        return self.__get_table(table).get(where=where)
    
    def get_single(self, table, where=None):
        """get specified object(s) from given table"""
        return self.__get_table(table).get_single(where=where)
    
    def new(self, table):
        """creates new empty DBObject"""
        return DBObject(self.__get_table(table))
        
