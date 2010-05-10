#!/bin/bash

for dev in /dev/[hs]d[1-9]*
do
    mdadm --examine --brief "$dev"
done | perl -e '
    use strict;
    my %uid= ();
    while (<>) {
        if (/num\-devices\=(\d+) UUID\=(\S+)\s/) {
            $uid{$2}= {num => $1, count => 0,} unless defined $uid{$2};
            $uid{$2}{count}++;
        }
    }
    my $failed= 0;
    for my $uid (keys %uid) {
        if ($uid{$uid}{num} == $uid{$uid}{count}) {
            print "UID $uid is complete\n";
        }
        else {
            print "UID $uid is not complete!\nFound only $uid{$uid}{count} of $uid{$uid}{num} devices\n";
            $failed= 1;
        }
    }
    exit $failed;
'

if [ "$?" -ne "0" ]; then
    echo "device failed!"
else
    if grep "md0 : active" /proc/mdstat > /dev/null; then
        echo "/dev/md0 already startet"
    else
        mdadm --assemble --scan
        sleep 2
    fi
    if grep "/mnt/vandusen" /proc/mounts > /dev/null; then
        echo "already mounted"
    else
        mount /mnt/vandusen
    fi

    sleep 2

    watch -d "cat /proc/mdstat ; echo ; mdadm --detail /dev/md? 2>/dev/null"
fi
