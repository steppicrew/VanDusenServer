#!/bin/bash

perl -e '
	my $in;
	my $sum= 0;
	while (<>) {
		$in= 1 if /Dec  6 23/;
		next unless $in;
		last if /^Session finished/;
		if (/\(([\d\,]+)\)\n/) {
			my $size= $1;
			$size=~s/\,//g;
			$sum += $size;
		}
	}
	print "Total: $sum\n";
' < /mnt/vandusen/ftp.log

