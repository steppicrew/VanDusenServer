#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Module presenting some logging functionality"""
import os

COLORS = {
    'reset': 0, 'bold': 1, 'dark': 2, 'underline': 4,  'underscore': 4,
    'blink': 5,  'reverse': 7, 'concealed': 8,

    'black': 30,  'red': 31, 'green': 32, 'yellow': 33,
    'blue': 34, 'magenta': 35, 'cyan': 36, 'white': 37,

    'on_black': 40,  'on_red': 41, 'on_green': 42, 'on_yellow': 43,
    'on_blue': 44, 'on_magenta': 45, 'on_cyan': 46, 'on_white': 47,
}

DEBUG_LEVELS = {
    'standard': 4,
    'debug': 5,
    'info': 4,
    'warning': 3,
    'error': 2,
    'critical': 1,
    'none': 0,
}
DEBUG_LEVEL = DEBUG_LEVELS['standard']

def TO_UNICODE(string):
    """converts string to unicode"""
    try:
        # wroks if string is unicode already
        return unicode(string, "utf-8")
    except:
        pass
    try:
        # works if string is iso8859-1
        return unicode(string, "iso-8859-1")
    except:
        pass
    # try simple coding
    return unicode(string)

class Logger(object):
    """Class do some logging"""
    def __init__(self, logfile='./ftp.log'):
        self.__debug_level = DEBUG_LEVELS['standard']
        self.__progress = False
        self.__file = open(logfile, 'a');

    def __color(self, color):
        """returns approriate color string"""
        return '\033[' + \
            ";".join(
                [
                    unicode(COLORS[c_lower])
                        for c_lower in [col.lower() for col in color]
                            if c_lower in COLORS
                ]
            ) + \
            'm'

    def __reset(self):
        """returns reset string"""
        return self.__color(('reset', ))

    def colored(self,  color,  lines):
        """returns lines with given colors"""
        return [
            self.__color(color) + TO_UNICODE(line) + self.__reset()
                for line in lines
        ]

    def __raw(self, lines):
        """prints and flushes lines"""
        os.sys.stdout.write(u"\n".join(lines).encode('utf-8', 'ignore'))
        os.sys.stdout.flush()

    def log(self, *lines):
        """prints to file"""
        lines = [TO_UNICODE(line) for line in lines]
        lines.append('')
        self.__file.write(u"\n".join(lines).encode('utf-8', 'ignore'))
        self.__file.flush()

    def progress(self, lines):
        """prints progress"""
        if self.__progress and len(lines):
            lines[0] = "\r" + lines[0]
        self.__progress = True
        self.__raw(lines)

    def print_lines(self, lines):
        """prints given lines with trailing lf"""
        lines.append('')
        if self.__progress:
            lines[0] = "\r" + lines[0]
            self.__progress = False
        self.__raw(lines)

    def debug(self, *lines):
        """print a debug message"""
        if self.__debug_level >= DEBUG_LEVELS['debug']:
            self.print_lines([TO_UNICODE(_) for _ in lines])

    def info(self, *lines):
        """prints an info message"""
        if self.__debug_level >= DEBUG_LEVELS['info']:
            self.print_lines(self.colored(('green', 'bold'),  lines))

    def warning(self, *lines):
        """prints a warning message"""
        if self.__debug_level >= DEBUG_LEVELS['warning']:
            self.print_lines(self.colored(('magenta', 'bold'),  lines))

    def error(self, *lines):
        """prints an error message"""
        if self.__debug_level >= DEBUG_LEVELS['error']:
            self.print_lines(self.colored(('red', 'bold'),  lines))

    def critical(self, *lines):
        """prints a critical error message"""
        if self.__debug_level >= DEBUG_LEVELS['critical']:
            self.print_lines(self.colored(('on_red', 'bold',  'white'),  lines))

    def set_debug_level(self, s_debug_level):
        """Sets debug level"""
        self.__debug_level = DEBUG_LEVELS[s_debug_level.lower()]

    def get_debug_level(self):
        """Returns debug level"""
        return self.__debug_level

