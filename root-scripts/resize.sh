#!/bin/bash

#tune2fs -O ^has_journal /dev/md0
resize2fs -p -S 16 /dev/md0
e2fsck -n /dev/md0
tune2fs -j /dev/md0
