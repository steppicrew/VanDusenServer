#!/bin/bash

devices=( `cat "/proc/mdstat" | perl -ne 'print "$1 " while s/^.*?(\w+)\[\d+\]\s//;'`)

running=""
for drive in "${devices[@]}"
do
    if smartctl -l selftest -F samsung3 /dev/$drive | grep "Self-test routine in progress" > /dev/null; then
        running=1
    fi
done

if [ -z "$running" ]; then
    for drive in "${devices[@]}"; do
        smartctl -t long -F samsung3 /dev/$drive
    done
fi

watch -d "for drive in ${devices[@]}; do echo; echo \"/dev/\$drive:\"; smartctl -l error -l selftest -F samsung3 /dev/\$drive | grep -v 'Completed without error' | grep -i -E 'error|sd|# 1'; done"

