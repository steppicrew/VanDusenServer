#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Manages Hoedat DB"""
from HoerdatDB import HoerdatDB
from HoerdatData import HoerdatData
from Logger import TO_UNICODE
import httplib

HOERDAT_HOST = "www.hoerdat.in-berlin.de"
HOERDAT_URL = "/select.php"

class Hoerdat(object):
    """Class to fetch information from Hoerdat"""
    def __init__(self, hoerdb):
        super(Hoerdat, self).__init__()
        self.__hddb = hoerdb
        self.data = {
            'filename': None,
            'hoerdat': None,
        }

    def set_filename(self,  u_file, md5):
        """sets current file name"""
        self.data['filename'] = u_file
        self.data['hoerdat'] = HoerdatData(self.__hddb, u_file, md5)
        return self.data['hoerdat'].get_data('title')

    def get_best_match(self, l_data):
        """returns entry with highest ranking"""
        if not len(l_data):
            return None
        lt_data = [(_, _.rank(self.data['hoerdat'])) for _ in l_data]
        print 'ranks:', ', '.join([unicode(_[1]) for _ in lt_data])
        lt_data.sort(lambda a, b: cmp(b[1], a[1]))
        return lt_data[0]


    def fetch_data(self):
        """fetch missing data from hoerdat"""
        http_conn = httplib.HTTPConnection(HOERDAT_HOST)
        header, body = self.data['hoerdat'].build_request()
        http_conn.request('POST', HOERDAT_URL, body, header)
        http_resp = http_conn.getresponse()
        if http_resp.status == 200:
            return self.__parse_page(TO_UNICODE(http_resp.read()))
        return []

    def __parse_page(self, u_data):
        """parse hoerdat page"""
        l_result = []
        for u_table in u_data.split('<table>'):
            index = u_table.find('</table>')
            if index < 0:
                continue
            l_result.append(self.__parse_table(u_table[:index]))
        return l_result

    def __parse_table(self, u_table):
        """parse single hoerdat record"""
        hd_result = HoerdatData(self.__hddb)
        for u_tr in u_table.split('<tr>'):
            index = u_tr.find('</tr>')
            if index < 0:
                continue
            key, value = self.__parse_tr(u_tr[:index])
            hd_result.set_table_data(key, value)

        return hd_result

    def __parse_tr(self, u_tr):
        """parse hoerdat record's line"""
        key, value = None, None
        t_split = u_tr.split('<th', 1)
        if len(t_split) > 1:
            tail = t_split[1].split('>', 1)[1]
            content, tail = tail.split('</th>', 1)
            return 'title', content.strip()

        t_split = u_tr.split('<td', 1)
        if len(t_split) > 1:
            tail = t_split[1].split('>', 1)[1]
            content, tail = tail.split('</td>', 1)
            key = content.strip().lower()
            t_split = tail.split('<td', 1)
            if len(t_split) <= 1:
                return None, None
            tail = t_split[1].split('>', 1)[1]
            content, tail = tail.split('</td>', 1)
            value = content.strip()
        return key, value


    def merge_data(self, best_match, rank=None):
	self.data['hoerdat'].merge_data(best_match, rank)

    def update(self):
	self.data['hoerdat'].copy_to_db()
