#!/bin/bash

( cd /mnt/vandusen/vandusen; ls -Rohp | perl -ne '
    s/^d.*\/\n//;
    s/^insgesamt .*\n//;
    s/^[\-rw]{10}.*stephan //;
    s/^(\s*\S{2,4}) .{12}\d* /$1/;
    s/\n/\r\n/;
    print;
' | iconv -t iso-8859-1 -f utf-8 -c -) > "dir.txt"

