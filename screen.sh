#!/bin/bash

screen -w
cd /mnt/vandusen/scripts/wui
git pull

cfile=`mktemp`

cat > "$cfile" << EOT
screen './wui-debug.pl'
screen '../ogg-server/ogg-server.pl'
EOT

screen -d -m -U -c "$cfile" &

# screen './wui-debug.pl'

