#!/bin/bash

source "`dirname "$0"`/.settings"

echo "deprecated..."
exit

if sqlite3 "$hoerdat_db" '.schema files_md5' | grep -i CREATE > /dev/null; then
    echo "already done"
else
    sqlite3 "$md5_db" '.dump' | perl -ne '
        s/^INSERT INTO \"files\"/INSERT INTO \"files_md5\"/;
        s/^CREATE TABLE files/CREATE TABLE files_md5/;
        s/\sON\sfiles\s\(/ ON files_md5 \(/;
        print;
    ' | sqlite3 "$hoerdat_db"
fi


