#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Module to fetch ftp files"""
from Logger import Logger, TO_UNICODE
from FTPDB import FTPDB
from ftplib import FTP,  all_errors, error_perm
import sys
import re
import os
import time
import socket
import sqlite3
import random

# size of files where no "similar file serach" is done
MIN_FUZZY_MATCH_SIZE = 1024 * 1024 * 10
# time difference wherein files should be assumed unchanged
# (one hour+ to include DST/ST changes)
TIME_TOLERANCE = 24 * 60 * 60 + 100
# length of progress bar
PROGRESS_SIZE = 80
# block size for ftp download
FTP_BLOCKSIZE = 4096
# timeout for ftp connections
FTP_TIMEOUT = 180.0
# delay before try to reconnect if connection closed/failed
FTP_RECONNECT_DELAY = 60

class FTPFetch:
    """A simple class to FTP files."""
    def __init__(self,  host, port,  credentials, params):
        """Requires host name, user name, password and destination directory."""
        self.__ftp = None
        self.__ftp_data = {
            'host': host,
            'port': port,
            'credentials': credentials,
        }
        if 'logger' in params:
            self._logger = params['logger']
        else:
            self._logger = Logger()

        def get_param(name, default):
            """Gets parameters or sets default value"""
            if name in params:
                return params[name]
            return default

        self.params = {
            'dstdir': os.path.realpath(get_param('dstdir', '.')),
            'db': os.path.realpath(get_param('db', './ftp.db')),
            're_ignore': [re.compile(r) for r in get_param('ignore', [])],
            'old_cleanup' : get_param('old_cleanup', 0),
            'hidden_dirs' : get_param('possible_hidden_dirs', []),
        }

        self.__ftpdb = FTPDB(
            self.params['db'], self.params['dstdir'], params = params,
        )

        self.data = {
            'denied_dirs': [],
        }
        self.__stats = {
            'all_files': 0,
            'all_dirs': 0,
            'failed': 0,
            'all_size': 0,
            'downloaded_size': 0,
            'downloaded_files': 0,
        };

        self.dupmerge = get_param('dupmerge', None)
        # standard is to reverse order because we pop from queue
        if get_param('reverse', 0):
            self.sortorder = lambda x: x
        else:
            self.sortorder = lambda x: reversed(list(x))
        socket.setdefaulttimeout(FTP_TIMEOUT)
        self._logger.log("", "Starting new session at " + time.asctime())

    def __login(self,  trycount= -1):
        """Tries to connect to host."""
        self.close()
        i_trynum = 1
        while i_trynum != trycount + 1:
            self._logger.info("Trying to connect to " + self.__ftp_data['host']
                        +  " (try " + unicode(i_trynum) + ")...")
            try:
                self.__ftp = FTP()
                credentials= random.choice(self.__ftp_data['credentials'])
                try:
                    self.__ftp.connect(self.__ftp_data['host'], self.__ftp_data['port'])
                    self.__ftp.login(
                        credentials['username'],
                        credentials['password']
                    )
                    self._logger.info("done (" + credentials['username'] + ")")
                    return 1
                except all_errors:
                    self._logger.error(
                        "Could not authenticate to " + self.__ftp_data['host'] + " as " + credentials['username'] + "/" + credentials['password']

                    )
            except all_errors:
                self._logger.error(
                    "Could not connect to " + self.__ftp_data['host']
                )
            i_trynum += 1
            time.sleep(FTP_RECONNECT_DELAY)
        return 0

    def close(self):
        """Closes any open ftp connection."""
        if not self.__ftp:
            return
        try:
            self.__ftp.quit()
            self.__ftp.close()
        except all_errors:
            self._logger.error("Closing connection failed. Doing hard close.")
        finally:
            self.__ftp = None
            self._logger.info("Connection closed")

    def iterator(self, dirs):
        """Returns iterator to fetch given dirs."""
        # add files in reverse order because we pop entries
        l_queue = [('d',  u_dir.encode('iso-8859-1')) for u_dir in reversed(dirs)]

        if self.params['old_cleanup']:
            self.__ftpdb.prepare_files(list(dirs))

        def result():
            """Returns iterator's result and finishes ftp files db
            if finished"""
            if len(l_queue):
                return 1
            self._logger.info(
                "",
                "Dir count: " + self.format_num(self.__stats['all_dirs']),
                "File count: " + self.format_num(self.__stats['all_files']),
                "Failed: " + self.format_num(self.__stats['failed']),
                "Size: " + self.format_num(self.__stats['all_size']) + " Bytes",
                "Size downloaded: " + self.format_num(self.__stats['downloaded_size']) + " Bytes",
                "Files downloaded: " + self.format_num(self.__stats['downloaded_files']),
            )
            self._logger.log(
                "",
                "Dir count: " + self.format_num(self.__stats['all_dirs']),
                "File count: " + self.format_num(self.__stats['all_files']),
                "Failed: " + self.format_num(self.__stats['failed']),
                "Size: " + self.format_num(self.__stats['all_size']) + " Bytes",
                "Size downloaded: " + self.format_num(self.__stats['downloaded_size']) + " Bytes",
                "Files downloaded: " + self.format_num(self.__stats['downloaded_files']),
                "Session finished at " + time.asctime(),
                "",
            )
            if self.params['old_cleanup']:
                except_dirs = self.data['denied_dirs']
                except_dirs.extend(self.params['hidden_dirs'])
                self.__ftpdb.finish_files(except_dirs)
                self.cleanup_old_ftp_files(delete=1)
            return None

        done = [0, len(l_queue)]
        def iterator():
            """Anonymous iterator function"""
            t_entry = l_queue.pop()
            if not self.__ftp:
                self.__login()
            s_file = os.path.normpath(t_entry[1])
            u_file = TO_UNICODE(s_file)
            # check for files to ignore
            if [
                    re_expr.search(u_file)
                        for re_expr in self.params['re_ignore']
                            if re_expr.search(u_file) != None
                ]:
                self._logger.info("Skipping '" + u_file + "'")
                return result()

            try:
                if t_entry[0] == 'd':
                    self.__stats['all_dirs'] += 1;
                    done[0] += 1
                    self._logger.info("Entering '" + u_file + "'...")
                    l_new_files = self.__read_dir(s_file, u_file)
                    l_queue.append((
                        'D',
                        os.path.dirname(s_file),
                        (done[0], done[1])
                    ))
                    l_queue.extend(
                        self.sortorder(
                            sorted(
                                l_new_files,
                                lambda x,  y: cmp(x[1],  y[1])
                            )
                        )
                    )
                    done[0] = 0
                    done[1] = len(l_new_files)
                elif t_entry[0] == 'D':
                    self._logger.info("Returning to '" + u_file + "'")
                    done[0] = t_entry[2][0]
                    done[1] = t_entry[2][1]
                else:
                    self.__stats['all_files'] += 1;
                    done[0] += 1
                    self._logger.progress([
                        unicode(done[0]) + "/" + unicode(done[1])
                        + ": " + unicode(len(l_queue)) + " "
                    ])
                    self.__process_file(s_file, u_file)
            except error_perm:
                self._logger.error(
                    "Permission denied for file '" + u_file + "'. Ignoring."
                )
            except sqlite3.OperationalError:
                self._logger.error(
                    "Database Error for file '" + u_file + "'. Ignoring error."
                )
            except all_errors:
                self.__stats['failed'] += 1;
                self._logger.error(
                        "A FTP error occured: " + unicode(sys.exc_info()[0]),
                        "Readding file '" + u_file + "' to queue"
                )
                l_queue.append(t_entry)
                self.close()

            return result()

        return iterator

    def __read_dir(self, s_dir, u_dir):
        """Reads given directory from ftp and returns list of file tuples"""
        l_new_files = []
        re_expr = re.compile(
            '([d\-])[rwx\-]{9}\s+\d+\s+\w+\s+\w+'
            '\s+\d+\s+\w+\s+\w+\s+[\w\:]+\s(.+)'
        )

        def retr_lines(line):
            """Anonymous function to retrieve ftp data"""
#            m_line = re_expr.match(CONV_FROM_FTP(line))
            m_line = re_expr.match(line)
            if m_line != None:
                if m_line.group(2) not in ['.',  '..']:
                    l_new_files.append(
                        (m_line.group(1), os.path.join(s_dir,  m_line.group(2)))
                    )

        # if a hidden dir was found, remove it from hidden list
        if u_dir in self.params['hidden_dirs']:
            self.params['hidden_dirs'].remove(u_dir)
        try:
            self.__ftp.dir(s_dir,  retr_lines)
        except error_perm:
            self._logger.error(
                "Permission denied for dir '" + u_dir + "'. Ignoring."
            )
            self.data['denied_dirs'].append(u_dir)

        # type will be set to ASCII during ftp.dir(). so we set it
        # to BINARY to retrieve real file sizes
        self.__ftp.voidcmd("TYPE I")
        return l_new_files

    def __process_file(self, s_file, u_file):
        """Check if file already exists and download if needed"""
        i_size = self.__ftp.size(s_file)
        if not i_size:
            self._logger.info(
                "File '" + u_file
                + "' seems to be zero sized. Ignoring."
            )
            return

        # fix bug for large files (SIZE-command of vandusen-server returns upper 32 bit of a 64-bit number as '1')
        i_size_mask = (1 << 31) - 1
        if i_size > i_size_mask:
            u_local_file_name = self.__ftpdb.local_file_name(u_file)
            if os.path.exists(u_local_file_name):
                i_file_size = os.path.getsize(u_local_file_name)
                if i_size & i_size_mask == i_file_size & i_size_mask:
                    i_size = i_file_size

        t_date = self.__ftp.sendcmd('MDTM ' + s_file).partition(' ')
        i_date = 0
        if t_date[0] == '213':
            i_date = int(
                time.mktime(
                    time.strptime(
                        t_date[2],
                        "%Y%m%d%H%M%S"
                    )
                )
            )
        if self.__need_file(s_file, u_file, i_size,  i_date):
            self.__get_file(s_file, u_file, i_size,  i_date)

    def __need_file(self,  s_file, u_file,  i_size,  i_date):
        """Checks is given file is needed.

        returns 0 if file exists and is up to date
        returns 1 if file does not exist
        returns 2 if size differs
        returns 3 if file is significant newer
        returns -1 on error
        """
        self.__stats['all_size'] += i_size;
        u_local_file_name = self.__ftpdb.local_file_name(u_file)
        i_last_ftp_date = self.__ftpdb.get_last_date(u_local_file_name)
        if i_last_ftp_date:
            self.__ftpdb.touch_file(u_local_file_name)

        t_file_data= self.dupmerge.file_exists(u_local_file_name)
        if t_file_data == None:
            if i_size > MIN_FUZZY_MATCH_SIZE:
                # check for similar files
                u_file_hash = self.__file_hash(u_local_file_name)
                for u_sim_file in self.dupmerge.get_files_by_size(i_size):
                    if self.__file_hash(u_sim_file) != u_file_hash:
                        continue
                    self._logger.info(
                        "File '" + u_local_file_name
                        + "' seems to be a duplicate of '" + u_sim_file
                        + "'. Hardlinking."
                    )
                    self.dupmerge.hardlink(u_sim_file,  u_local_file_name)
                    return self.__need_file(s_file, u_file,  i_size,  i_date)
            self._logger.debug("File '" + u_file + "' does not exist.")
            return 1
        s_md5= t_file_data[2]
        if not i_last_ftp_date:
            self.__ftpdb.insert_file(u_local_file_name, i_size, i_date, s_md5)
            i_last_ftp_date = int(os.path.getmtime(u_local_file_name))

        i_file_size = os.path.getsize(u_local_file_name)
        if i_file_size != i_size:
            self._logger.info(
                "Size of file '" + u_file + "' differs (" + self.format_num(i_file_size)
                + " != " + self.format_num(i_size) + ")."
            )
            return 2
        if i_last_ftp_date + TIME_TOLERANCE < i_date:
            self._logger.info(
                "Date of file '" + u_file + "' differs (" + unicode(i_last_ftp_date)
                + " != " + unicode(i_date) + ")."
            )
            return 3
        if i_last_ftp_date != i_date:
            self.__ftpdb.update_date_file(u_local_file_name, i_date)
        self._logger.debug("File '" + u_file + "' seems to be up to date.")
        return 0

    def __resolve_duplicates(self,  u_file):
        """Hard links duplicates to given file"""
        l_duplicates = [
            (os.stat(_).st_ino,  _)
                for _ in self.dupmerge.get_duplicates(u_file)
                    if os.path.isfile(_)
        ]

        t_base_file = None
        if os.path.isfile(u_file):
            t_base_file = (os.stat(u_file).st_ino,  u_file)
        else:
            l_duplicates.append((-1,  u_file))
            t_base_file = l_duplicates.pop(0)
        for t_file in l_duplicates:
            if t_file[0] == t_base_file[0]:
                continue
            self._logger.info(
                "File '" + t_file[1] + "' is an unlinked duplicate of '"
                + t_base_file[1] + "'. Hardlinking."
            )
            self.dupmerge.hardlink(t_base_file[1],  t_file[1])

    def __file_hash(self,  u_file):
        """Builds has string for given file name"""
        # \w ae oe ue Ae Oe Ue sz
        return  ' '.join(
            sorted(
                re.split(
#                    u'[^\w\xe4\xf6\xfc\xc4\xd6\xdc\xdf]+',
#                    u'[^\wäöüÄÖÜß]+',
                    u'[^a-zA-Z0-9äöüÄÖÜß]+',
                    os.path.splitext(os.path.basename(u_file.lower()))[0]
                )
            )
        )

    def __get_file(self,  s_file, u_file,  i_size,  i_date):
        """Gets file via ftp and sets date accordingly"""
        self.__stats['downloaded_files'] += 1;
        self.__stats['downloaded_size'] += i_size;
        u_local_file_name = self.__ftpdb.local_file_name(u_file)
        u_tmp_file_name = u_local_file_name + ".tmp." + unicode(os.getpid())
        self.dupmerge.prepare_file(u_tmp_file_name)
        fd_file = open(u_tmp_file_name,  'wb')

        u_unit = 'B'
        i_unit = 1
        if i_size > 1024 * 1024 * 10:
            u_unit = 'MB'
            i_unit = 1024 * 1024
        elif i_size > 1024 * 10:
            u_unit = 'KB'
            i_unit = 1024

        u_progress_base = (" " * (PROGRESS_SIZE + 1)) + "] "
        u_size_part = "/" + self.format_num(i_size // i_unit) + u_unit

        # we have to reference last progress's value via list
        # because of python's scoping
        u_last_progress = [""]
        def print_progress():
            """Anonymous function to print progress bar"""
            i_cur_size = os.path.getsize(u_tmp_file_name)
            i_count = min(
                PROGRESS_SIZE,
                i_cur_size * PROGRESS_SIZE // i_size
            )
            u_progress = \
                u_progress_base + self.format_num(i_cur_size // i_unit) \
                + u_size_part + "\r[" + ("#" * i_count)

            if u_last_progress[0] != u_progress:
                self._logger.progress([u_progress])
                u_last_progress[0] = u_progress

        def write_block(data):
            """Anonymous function to write ftp data to file"""
            fd_file.write(data)
            print_progress()

        self._logger.info("Getting file '" + u_file + "'")
        print_progress()

        try:
            self.__ftp.retrbinary(
                'RETR ' + s_file,
                write_block,
                FTP_BLOCKSIZE
            )
            fd_file.close()
            print_progress()
            self._logger.progress(["\n"])
        except:
            fd_file.close()
            os.remove(u_tmp_file_name)
            self._logger.error(" ***ERROR*** ")
            raise

        i_real_size = os.path.getsize(u_tmp_file_name)
        if i_size != i_real_size:
            self._logger.warning(
                    "Size of '" + u_file + "' differs from reported!",
                    "Real size: " + self.format_num(i_real_size) + " Reported size: "
                        + self.format_num(i_size)
            )
        os.utime(u_tmp_file_name, (i_date,  i_date))
        self.dupmerge.rename_file(u_tmp_file_name,  u_local_file_name)
        self.__ftpdb.insert_file(u_local_file_name,  i_real_size,  i_date)
        self.__resolve_duplicates(u_local_file_name)
        self._logger.log("File '" + u_file + "' downloaded (" + self.format_num(i_real_size) + ")")

    def cleanup_old_ftp_files(self, delete = 0):
        """delete all not unique files from not present ftp"""
        files_to_remove = []
        for t_file in self.__ftpdb.get_old_files():
            u_file = self.__ftpdb.local_file_name(t_file)
            if not os.path.exists(u_file):
                self.__ftpdb.remove_file(t_file)
                continue
            for dup in self.dupmerge.get_duplicates(u_file):
                if dup in files_to_remove:
                    continue
                if not os.path.exists(dup):
                    self.__ftpdb.remove_file(dup)
                    continue
                self._logger.warning("Would remove file '" + u_file + "'")
                self._logger.info("(Duplicate: '" + dup + "')")
                files_to_remove.append(u_file)
                break
        if not delete:
            return
        for u_file in files_to_remove:
            self._logger.warning("Remove file '" + u_file + "'")
            self.dupmerge.remove_file(u_file)
            self.__ftpdb.remove_file(u_file)
            os.remove(u_file)

    def link_all_duplicates(self):
        """links all duplicates"""
        duplicates = []
        for md5 in self.dupmerge.get_all_duplicates():
            for u_file in self.dupmerge.get_files_by_md5(md5):
                duplicates.append(u_file)
                break

        for u_file in duplicates:
            self.__resolve_duplicates(u_file)

    def format_num(self, i_num):
        """formats number with thousand's separator"""
        import locale
        for code in ('en_GB', 'en_US', 'de_DE'):
            try:
                locale.setlocale(locale.LC_ALL, code)
                return locale.format('%d', i_num, True)
            except:
                self._logger.warning("Could not encode number " + code + " " + unicode(i_num))
        return unicode(i_num)

