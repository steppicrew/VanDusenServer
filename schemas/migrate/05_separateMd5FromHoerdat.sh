#!/bin/bash

source "`dirname "$0"`/.settings"

if sqlite3 "$hoerdat_db" '.schema files_md5' | grep -i CREATE > /dev/null; then
    test -f "$md5_db" && echo "deleting '$md5_db'" && rm "$md5_db"

    echo "dumping 'files_md5' and inserting as 'files' in '$md5_db'"
    sqlite3 "$hoerdat_db" '.dump files_md5' | perl -ne '
        s/^INSERT INTO \"files_md5\"/INSERT INTO \"files\"/;
        s/^CREATE TABLE files_md5/CREATE TABLE files/;
        s/\sON\sfiles_md5\s\(/ ON files \(/;
        print;
    ' | sqlite3 "$md5_db" \
    && echo "dropping table 'files_md5'" && sqlite3 "$hoerdat_db" 'DROP TABLE files_md5' \
    && echo "compressing '$hoerdat_db'" && ( sqlite3 "$hoerdat_db" '.dump' | sqlite3 "$hoerdat_db.tmp" ) && rm "$hoerdat_db" && mv "$hoerdat_db.tmp" "$hoerdat_db" \
    && echo "done"
else
    echo "already done"
fi


