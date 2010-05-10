#!/bin/bash

source "`dirname "$0"`/.settings"

if sqlite3 "$hoerdat_db" '.schema files' | grep -i length > /dev/null; then
    echo "already done"
else
    sqlite3 "$hoerdat_db" 'ALTER TABLE files ADD length INTEGER'
fi


