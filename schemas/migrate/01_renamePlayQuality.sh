#!/bin/bash

source "`dirname "$0"`/.settings"
TABLE="plays"
TMP_TABLE="tmp_$TABLE"
RENAME_FROM="quality"
RENAME_TO="rating"

db="$hoerdat_db"
old_db="$db.$$"

SCHEMA=`sqlite3 "$db" ".schema $TABLE"`

if echo "$SCHEMA" | grep -i quality > /dev/null; then
    echo "ALTER TABLE $TABLE RENAME $RENAME_FROM TO $RENAME_TO..."
    cp "$db" "$old_db"
    NEWSCHEMA=`echo "$SCHEMA" | perl -ne 's/\b'"$RENAME_FROM"'\b/'"$RENAME_TO"'/i; print;'`
    TMPSCHEMA=`echo "$NEWSCHEMA" | perl -ne 's/CREATE\s+TABLE\s+'"$TABLE"'\b/CREATE TEMP TABLE '"$TMP_TABLE"'/i; print;'`
    
    echo "Changing schmea of '$TABLE' from"
    echo "$SCHEMA"
    echo "to"
    echo "$NEWSCHEMA"
    echo "Press ^C to break or ENTER to continue..."
    read
    
    sqlite3 "$db" << EOF
BEGIN TRANSACTION;
$TMPSCHEMA
INSERT INTO $TMP_TABLE SELECT * FROM $TABLE;
DROP TABLE $TABLE;
$NEWSCHEMA
INSERT INTO $TABLE SELECT * FROM $TMP_TABLE;
DROP TABLE $TMP_TABLE;
COMMIT;
EOF
    OLD_COUNT=`sqlite3 "$db" "SELECT count(*) FROM $TABLE"`
    NEW_COUNT=`sqlite3 "$old_db" "SELECT count(*) FROM $TABLE"`
    if [ "$OLD_COUNT" -eq "$NEW_COUNT" ]; then
        echo "Successfully tranferred $NEW_COUNT records!"
        rm "$old_db"
    else
        echo "FAILED!"
        mv -f "$old_db" "$db"
    fi
fi


