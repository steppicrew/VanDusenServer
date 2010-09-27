#!/bin/bash

screen -w
cd /mnt/vandusen/scripts/wui
git pull

cfile=`mktemp`

cat > "$cfile" << EOT
screen './wui-debug.pl'
screen '../ogg-server/ogg-server.pl'
EOT

screen -c "$cfile"
rm "$cfile"

# screen './wui-debug.pl'
