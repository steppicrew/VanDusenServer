#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Manages single Hoerdat record"""
import re
import urllib
import os.path
from Logger import TO_UNICODE

RE_STRIPEXT = re.compile('^(?P<basename>.+)\.mp\d$')
RE_FILEMATCH1 = re.compile('^(?P<author>.+?)_(?P<title>.+)_(?P<tail>.+?)$')
RE_FILEMATCH2 = re.compile('^(?P<author>.+?)\-(?P<title>.+)\-(?P<tail>.+?)$')
RE_TITLEMATCH = re.compile(
    '^(?P<title>.+)\.\.\.$'
)
RE_TITLEMATCH_PARTS = re.compile(
    '^(?P<title>.+) +'
    '0*(?P<part_num>\d+)v0*(?P<part_count>\d+)$'
)
RE_TITLEMATCH_ADD = re.compile(
    '^(?P<title>.+) +'
    '(?P<addition>\(.+\))$'
)
RE_AUTHORMATCH1 = re.compile('^(?P<name>.+)\, *(?P<given_name>.+)$')
RE_HTTP_AUTHORMATCH = re.compile('<b>\s*(?P<author>.+)\s*</b>')
RE_AUTHORMATCH2 = re.compile('^(?P<given_name>.+) +(?P<name>.+?)$')
RE_TAILMATCH = re.compile(
    '^(?P<stations>.+)\, *'
    '(?P<year>\d{4})(\-(?P<quality>\d))?(\-\((?P<audio>.+)\))?$'
)

RE_HTTP_BR = re.compile('<br ?/?>')
RE_HTTP_WS = re.compile('\s+')
RE_HTTP_TAG = re.compile('<.+?>')
RE_HTTP_PRODUCTION = re.compile('^\s*(?P<stations>[\w/]+)\s+(?P<year>\d+)')

HOERDAT_SEARCH_FIELDS = {
    'title': 'ti',
    'author_name': 'au.an',
    'author_given_name': 'au.av',
    'station': 'pr',
    'year': 'yr',
    'director': 're.an'
}

HOERDAT_SEARCH_ORDER = [
    'title', 'author_name', 'author_given_name',
    'year'
]

HOERDAT_KEYS = [
    'hoerdat_id', 'title', 'arranger', 'roles', 'author_name', 'author_given_name',
    'description', 'director', 'genres', 'keywords', 'other_titles', 'stations', 'year',
]

class HoerdatData(object):
    """Class to store one Hoerdat record"""
    def __init__(self, hddb, u_file = None, md5 = None):
        self.__hddb = hddb
        self.__db_funcs = {}
        self.__data = {}
        self.parse_name(u_file, md5)
        self.set_funcs = {
            'title': lambda u_title:
                self.__http_parse_default('title', u_title),
            'autor(en)': lambda u_author:
                self.__http_parse_author(u_author),
            'auch unter dem titel': lambda u_titles:
                self.__http_parse_default_list('other_titles', u_titles),
            'produktion': lambda u_production:
                self.__http_parse_production(u_production),
            'regisseur(e)': lambda u_director:
                self.__http_parse_default('director', u_director),
            'bearbeiter': lambda u_arranger:
                self.__http_parse_default('arranger', u_arranger),
            'übersetzer': lambda u_translator:
                self.__http_parse_default('translator', u_translator),
            'schlagwörter': lambda u_keywords:
                self.__http_parse_default_list('keywords', u_keywords),
            'genre(s)': lambda u_genres:
                self.__http_parse_default_list('genres', u_genres),
            'inhaltsangabe': lambda u_description:
                self.__http_parse_default('description', u_description),
            'mitwirkende': lambda u_roles:
                self.__http_parse_roles(u_roles),
            'links': lambda u_links:
                self.__http_parse_id(u_links)
        }


    def __init_data(self):
        """init data hash"""
        self.__data = {
            'id': None,
            'hoerdat_id': None,
            'title': None,

            'addition': None,
            'arranger': None,
            'roles': {},
            'audio': None,
            'author_name': None,
            'author_given_name': None,
            'description': None,
            'director': None,
            'file_rank': None,
            'file_name': None,
            'genres': [],
            'keywords': [],
            'part_count': None,
            'part_num': None,
            'other_titles': [],
            'quality': None,
            'stations': [],
            'year': None,

            'other': {},
        }

    def parse_name(self, u_file = None, md5 = None):
        """parse given file name"""
        self.__init_data()
        if u_file == None:
            return
        self.__data['file_name'] = u_file
        self.__data['md5'] = md5
        if md5:
            db_file = self.__hddb.get_single('files', {'md5': md5})
            if db_file:
                self.__fill_db_data(db_file=db_file)
                if self.__data['title']:
                    return True
        self.__parse_mp3()
        match = RE_STRIPEXT.search(os.path.basename(u_file))
        if match != None:
            if self.__parse_basename(match.group('basename')):
                self.__try_fetch_from_db()
                return 1
        return None

    def __parse_mp3(self):
        """try to parse ID3-tag"""
        def set_data(field, value):
            self.__data[field] = value
        id3_mapping = {
            'ARTIST': lambda author: self.__parse_author(author),
            'TITLE':  lambda title: self.__parse_title(title),
            'YEAR':   lambda year: set_data('year', year),
        }

        import ID3
        try:
            id3 = ID3.ID3(self.__data['file_name'])
            for key, value in id3.items():
                if key in id3_mapping:
                    id3_mapping[key](value)
        except:
            return None

    def __parse_basename(self, u_basename):
        """parse base name, separating title, author, tail parts"""
        match = RE_FILEMATCH1.search(u_basename)
        if not match:
            match = RE_FILEMATCH2.search(u_basename)
        if match:
            self.__parse_title(match.group('title'))
            self.__parse_author(match.group('author'))
            self.__parse_tail(match.group('tail'))
            return 1
        return None

    def __parse_title(self, u_title):
        """parse title, separating part numbers and additions"""
        if u_title == None:
            return
        def title_strip(u_title):
            """strips optional '...'"""
            match = RE_TITLEMATCH.search(u_title)
            if match:
                return match.group('title')
            return u_title

        match = RE_TITLEMATCH_PARTS.search(u_title)
        if match:
            if not self.__data['title']:
                self.__data['title'] = title_strip(match.group('title'))
            self.__data['part_num'] = match.group('part_num')
            self.__data['part_count'] = match.group('part_count')
            return
        match = RE_TITLEMATCH_ADD.search(u_title)
        if match:
            if not self.__data['title']:
                self.__data['title'] = title_strip(match.group('title'))
            self.__data['addition'] = match.group('addition')
            return
        if not self.__data['title']:
            self.__data['title'] = title_strip(u_title)

    def __parse_author(self, u_author):
        """parse author's name"""
        if u_author == None or self.__data['author_name']:
            return
        match = RE_AUTHORMATCH1.search(u_author)
        if not match:
            match = RE_AUTHORMATCH2.search(u_author)
        if match:
            self.__data['author_name'] = match.group('name')
            self.__data['author_given_name'] = match.group('given_name')
            return
        self.__data['author_name'] = u_author

    def __parse_tail(self, u_tail):
        """parse station, year, and quality"""
        if u_tail == None:
            return
        match = RE_TAILMATCH.search(u_tail)
        if match:
            self.__data['stations'] = match.group('stations').split(',')
            if not self.__data['year']:
                self.__data['year'] = match.group('year')
            self.__data['quality'] = match.group('quality')
            self.__data['audio'] = match.group('audio')

    def build_request(self):
        """build http request from data"""
        fields = 'abc'
        result = {}
        index = 0
        for data_key in HOERDAT_SEARCH_ORDER:
            if not data_key in HOERDAT_SEARCH_FIELDS:
                continue
            data = self.get_data(data_key)
            if not data:
                continue
            if index >= len(fields):
                break
            result[fields[index]] = TO_UNICODE(self.get_data(data_key)).encode('iso-8859-1')
            index += 1
            result['col' + unicode(index)] = HOERDAT_SEARCH_FIELDS[data_key]
            result['bool' + unicode(index)] = 'and'

        header = {
            'Content-Type': 'application/x-www-form-urlencoded',
        }
        return header, urllib.urlencode(result)

    def __try_fetch_from_db(self):
        """tries to fetch play from db"""
        where = {}
        for data_key in HOERDAT_KEYS:
            if not self.__data[data_key] or hasattr(self.__data[data_key], '__iter__'):
                continue
            where[data_key] = self.__data[data_key]
        if not where:
            return
        db_play = self.__hddb.get_single('plays', where)
        if db_play:
            self.__fill_db_data(db_play=db_play)
            return True

    def set_table_data(self, u_field, u_text):
        """Sets data read from http table"""
        if not u_field or not u_text:
            return
        u_field = TO_UNICODE(u_field.strip(':'))
        if u_field in self.set_funcs:
            self.set_funcs[u_field](u_text)
        else:
            self.__http_parse_other(u_field, u_text)

    def __http_simplify(self, u_text):
        """removes html tags and replaces <br> with lf"""
        return "\n".join(self.__http_simplify_list(u_text))

    def __http_simplify_list(self, u_text):
        """removes duplicate white spaces, splits lines at <br>
        and removes all other html tags"""
        return [
            RE_HTTP_WS.sub(' ', RE_HTTP_TAG.sub('', _)) for _ in [
                _.strip() for _ in RE_HTTP_BR.split(u_text)
            ] if _ != ''
        ]

    def __http_parse_default(self, u_field, u_text):
        """default function to set text field"""
        self.__data[u_field] = self.__http_simplify(u_text)

    def __http_parse_default_list(self, u_field, l_text):
        """default function to set list fields"""
        self.__data[u_field] = self.__http_simplify(l_text).splitlines()

    def __http_parse_author(self, u_author):
        """parse http author"""
        match = RE_HTTP_AUTHORMATCH.search(u_author)
        if match:
            u_author = match.group('author')
        self.__parse_author(self.__http_simplify(u_author))

    def __http_parse_production(self, u_production):
        """parse production field"""
        match = RE_HTTP_PRODUCTION.search(u_production)
        if match:
            self.__data['stations'] = match.group('stations').split('/')
            self.__data['year'] = match.group('year')
            return
        self.__http_parse_other('production', u_production)

    def __http_parse_other(self, u_title, u_text):
        """parse unknown hoerdat data"""
        self.__data['other'][u_title] = self.__http_simplify(u_text)

    def __http_parse_id(self, u_text):
        """parse hoerdats links field for id"""
        t_split = u_text.split("&amp;n=", 1)
        if len(t_split) <= 1:
            return
        t_split = t_split[1].split("'>", 1)
        if t_split[0].isdigit():
            self.__data['hoerdat_id'] = t_split[0]

    def __http_parse_roles(self, u_roles):
        """parse role's list"""
        for u_line in [self.__http_simplify(_) for _ in u_roles.splitlines()]:
            t_split = u_line.rsplit(":", 1)
            if len(t_split) > 1:
                self.__data['roles'][t_split[0].strip()] = t_split[1].strip()
            else:
                if not '' in self.__data['roles']:
                    self.__data['roles'][''] = []
                self.__data['roles'][''].extend(
                    [
                        _ for _ in [
                            _.strip() for _ in u_line.split(',')
                        ] if _ and _ != 'u.a.'
                    ]
                )

    def print_data(self):
        """print complete data set"""
        result = [
            "#" * 80,
            self.get_data('title').upper(),
            "#" * 80,
        ]
        for key in sorted(self.__data.keys()):
            value = self.get_data(key)
            if value == None:
                continue
            result.append(key + ":\t" + unicode(value))
            result.append("-" * 80)
        return result

    def get_data(self, u_key):
        """returns data field"""
        if self.__data[u_key]:
            return self.__data[u_key]
        if u_key in self.__db_funcs:
            return self.__db_funcs[u_key]()
        return self.__data[u_key]

    def damerau_levenshtein_distance(self, first, second, damerau=1):
        """Find the Levenshtein distance between two strings.
        found at http://www.poromenos.org/node/87
        modified after reading http://en.wikipedia.org/wiki/Levenshtein_distance
            and http://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance
        modified by steppicrew
        """
        max_len = max(len(first), len(second)) + 1
        # function to normalize result between 0 (very different) to 1 (equal)
        result = lambda x: 1 - (0.0 + x)/max_len
        first_length = len(first)
        second_length = len(second)
        if max_len == 1:
            return result(1)
        distance_matrix = [
            [i + j for j in range(second_length+1)]
                for i in range(first_length+1)
        ]
        for i in xrange(first_length):
            for j in range(second_length):
                deletion = distance_matrix[i][j + 1] + 1
                insertion = distance_matrix[i + 1][j] + 1
                cost = 0
                if first[i] != second[j]:
                    cost = 1
                distance_matrix[i +1][j +1] = min(
                    insertion,
                    deletion,
                    distance_matrix[i][j] + cost,
                )
                if damerau and i > 0 and j > 0 and \
                    first[i] == second[j -1] and first[i -1] == second[j]:
                    distance_matrix[i +1][j +1] = min(
                        distance_matrix[i + 1][j +1],
                        distance_matrix[i - 1][j - 1] + cost
                    )
        return result(distance_matrix[-1][-1])

    def damerau_levenshtein_distance_optimized(self, first, second, damerau=1):
        """Find the Levenshtein distance between two strings.
        optimized for memory saving
        found at http://www.poromenos.org/node/87
        modified after reading http://en.wikipedia.org/wiki/Levenshtein_distance
            and http://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance
        modified by steppicrew
        """
        max_len = max(len(first), len(second)) + 1
        # function to normalize result between 0 (very different) to 1 (equal)
        result = lambda x: 1 - (0.0 + x)/max_len
        if damerau:
            damerau = 1
        first_length = len(first)
        second_length = len(second)
        if max_len == 1:
            return result(1)
        distance_matrix = [[j for j in range(second_length + 1)]]
        for i in xrange(first_length):
            distance_matrix.append([i +1 for j in range(second_length + 1)])
            for j in range(second_length):
                deletion = distance_matrix[-2][j + 1] + 1
                insertion = distance_matrix[-1][j] + 1
                cost = 0
                if first[i] != second[j]:
                    cost = 1
                distance_matrix[-1][j + 1] = min(
                    insertion,
                    deletion,
                    distance_matrix[-2][j] + cost
                )
                if damerau and i > 0 and j > 0 and \
                    first[i] == second[j-1] and first[i-1] == second[j]:
                    distance_matrix[-1][j + 1] = min(
                        distance_matrix[-1][j + 1],
                        distance_matrix[-3][j - 1] + cost
                    )
            if len(distance_matrix) > damerau + 1:
                distance_matrix.pop(0)
        return result(distance_matrix[-1][-1])

    def similarity(self, s1, s2):
        return self.damerau_levenshtein_distance_optimized(s1, s2)

    def rank(self, hd_other):
        """returns similarity rank"""
        result = 0
        if unicode(self.get_data('hoerdat_id')) == unicode(hd_other.get_data('hoerdat_id')):
            result += 1000
        for sub_rank, this, other in (
            (
                100,
                self.get_data('title').lower(),
                hd_other.get_data('title').lower(),
            ),
            (
                200,
                self.get_data('title'),
                hd_other.get_data('title'),
            ),
            (
                25,
                self.get_data('author_given_name'),
                hd_other.get_data('author_given_name'),
            ),
            (
                25,
                self.get_data('author_name'),
                hd_other.get_data('author_name'),
            ),
            (
                20,
                self.get_data('year'),
                hd_other.get_data('year'),
            ),
            (
                20,
                ','.join(sorted(self.get_data('stations'))),
                ','.join(sorted(hd_other.get_data('stations'))),
            ),
        ):
            if not this or not other:
                continue
            result += sub_rank * self.similarity(TO_UNICODE(this), TO_UNICODE(other))
        return result


    def get_db_fields_data(self, l_requested_fields):
        l_data = []
        l_fields = []
        for u_field in l_requested_fields:
            if u_field in self.__data:
                l_fields.append(u_field)
                l_data.append(self.get_data(u_field))
        return l_fields, tuple(l_data)

    def __fill_db_data(self, db_file=None, db_play=None):
        """fill __db_funcs"""
        def fact(func):
            """factory function for single objects"""
            value = []
            def result():
                """anonymous function for memoize"""
                if value:
                    return value[0]
                value.append(func())
                return value[0]
            return result

        def fact_list(func):
            """factory function for iteratable objects"""
            value = []
            value_set = [False]
            def _loop(func):
                """generator"""
                for sub_value in func():
                    value.append(sub_value)
                    yield sub_value
                value_set[0] = True
            def result():
                """anonymous function returns list or genrator"""
                if value_set[0]:
                    return value
                return _loop(func)
            return result

        def get_roles(func):
            """returns role's hash"""
            roles = {}
            for dbo_role in func():
                role = dbo_role.get('role')
                artist = dbo_role.get('artist').get('name')
                if role:
                    roles[role] = artist
                else:
                    if '' not in roles:
                        roles[''] = []
                    roles[''].append(artist)
            return roles
        def get_if_exists(dbo, field):
            """returns field if dbo is not None"""
            if dbo:
                return dbo.get(field)
            return None

        if not db_play:
            if not db_file:
                raise "You have to specify at least one of db_file or db_play."
            db_play = db_file.get('play')

        funcs = {
            '__play':       fact(lambda: db_play),
            '__title':      fact(lambda: funcs['__play']().get('title')),
            '__roles':      fact_list(lambda: funcs['__play']().get('roles')),
            '__author':     fact(lambda: funcs['__play']().get('author')),
            '__genres':     fact_list(lambda: funcs['__play']().get('genres')),
            '__keywords':   fact_list(lambda: funcs['__play']().get('keywords')),
            '__other_titles': lambda: [
                _
                    for _ in funcs['__play']().get('all_titles')
                        if _.primary_value() != funcs['__play']().get('title_id')
            ],
            '__stations':   fact_list(lambda: funcs['__play']().get('stations')),

            'hoerdat_id':  lambda: funcs['__play']().get('hoerdat_id'),
            'title':       lambda: funcs['__title']().get('title'),

            'addition':    lambda: funcs['__play']().get('addition'),
            'arranger':    lambda: get_if_exists(funcs['__play']().get('arranger'), 'name'),
            'audio':       lambda: funcs['__play']().get('audio'),
            'author_name': lambda: get_if_exists(funcs['__author'](), 'name'),
            'author_given_name': lambda: get_if_exists(funcs['__author'](), 'given_name'),
            'director':    lambda: get_if_exists(funcs['__play']().get('director'), 'name'),
            'description': lambda: funcs['__play']().get('description'),
            'genres':      lambda: [_.get('genre') for _ in funcs['__genres']()],
            'keywords':    lambda: [_.get('keyword') for _ in funcs['__keywords']()],
            'other_titles': lambda: [_.get('title') for _ in funcs['__other_titles']()],
            'roles':       fact(lambda: get_roles(funcs['__roles'])),
            'stations':    lambda: [_.get('station') for _ in funcs['__stations']()],
            'year':        lambda: funcs['__play']().get('year'),
        }
        if db_file:
            funcs['__file'] =     fact(lambda: db_file)
            funcs['part_count'] = lambda: funcs['__file']().get('part_count')
            funcs['part_num'] =   lambda: funcs['__file']().get('part_num')
            funcs['quality'] =    lambda: funcs['__file']().get('quality')
            funcs['file_rank'] =  lambda: funcs['__file']().get('file_rank')
        self.__db_funcs = funcs

    def merge_data(self, best_match, rank=None):
        """merge best_match's data with our"""
        for key in HOERDAT_KEYS:
            self.__data[key] = best_match.get_data(key)
        if rank != None:
            self.__data['file_rank'] = rank

    def copy_to_db(self):
        """flushes data to db, creating table entries if needed"""
        try:
            self.__hddb.db_begin_transaction()
            title = self.get_data('title')
            # if current hoerdat_id is different from old, remove binding to old db_play
            if self.get_data('hoerdat_id') and '__play' in self.__db_funcs:
                old_hoerdat_id= self.__db_funcs['hoerdat_id']();
                if old_hoerdat_id and unicode(old_hoerdat_id) != unicode(self.get_data('hoerdat_id')):
                    self.__db_funcs= {}
                    print "HOERDAT ID CHANGED FROM", old_hoerdat_id, "TO", self.get_data('hoerdat_id')
            if '__play' not in self.__db_funcs:
                db_play = None
                if self.get_data('hoerdat_id'):
                    db_play = self.__hddb.get_single('plays', {'hoerdat_id': self.get_data('hoerdat_id')})
                if db_play:
                    db_title = db_play.get('title')
                else:
                    db_play = self.__hddb.new('plays')
                    db_title = self.__hddb.new('titles')
                    db_title.set('title', title)
                    db_title.set('play_id', -1)
                    db_title.flush()
                    db_play.set('title', db_title)
                    db_play.flush()
                    db_title.set('play', db_play)
                    db_title.flush()
            else:
                db_title = self.__db_funcs['__title']()
                db_title.set('title', title)
                db_title.flush()
                db_play = self.__db_funcs['__play']()
            for prop in ('hoerdat_id', 'addition', 'audio', 'description', 'year', ):
                if prop in self.__data and self.__data[prop]:
                    db_play.set(prop, self.__data[prop])
            db_play.ref_or_create(
                'author',
                {
                    'name': self.get_data('author_name'),
                    'given_name': self.get_data('author_given_name'),
                },
            )
            db_play.ref_or_create(
                'arranger',
                {'name': self.get_data('arranger')},
            )
            db_play.ref_or_create(
                'director',
                {'name': self.get_data('director')},
            )
            db_play.xref(
                'genres',
                [{'genre': _} for _ in self.__data['genres']],
            )
            db_play.xref(
                'keywords',
                [{'keyword': _} for _ in self.__data['keywords']],
            )
            db_play.xref(
                'stations',
                [{'station': _} for _ in self.__data['stations']],
            )
            # build roles' data for single xref-call to allow dead-ref cleanup
            roles = self.get_data('roles')
            artists_where = []
            roles_data = []
            for role in roles:
                if role:
                    artists_where.append({'name': roles[role]})
                    roles_data.append({'role': role})
                else:
                    artists_where.extend([{'name': _} for _ in roles[role]])
                    roles_data.extend([{'role': None} for _ in roles[role]])
            db_play.xref(
                'artists',
                artists_where,
                roles_data,
            )
            db_play.flush()
            if '__file' not in self.__db_funcs:
                db_file = None
                if self.get_data('md5'):
                    db_file = self.__hddb.get_single('files', {'md5': self.get_data('md5')})
                if not db_file:
                    db_file = self.__hddb.new('files')
            else:
                db_file = self.__db_funcs['__file']()
            db_file.set('md5', self.get_data('md5'))
            db_file.set('play', db_play)
            for prop in ('part_num', 'part_count', 'quality', 'file_rank', ):
                if prop in self.__data and self.__data[prop]:
                    db_file.set(prop, self.__data[prop])
            db_file.flush()
            self.__fill_db_data(db_file=db_file, db_play=db_play)
            other_titles = list(self.get_data('other_titles'))
            for db_title in self.__db_funcs['__other_titles']():
                other_title = db_title.get('title')
                if other_title in other_titles:
                    other_titles.remove(other_title)
                else:
                    db_title.delete()
            for other_title in other_titles:
                if other_title == title:
                    continue
                db_title = self.__hddb.new('titles')
                db_title.set('title', other_title)
                db_title.set('play', db_play)
                db_title.flush()
            self.__hddb.db_commit()
        except:
            self.__hddb.db_rollback()
            raise
