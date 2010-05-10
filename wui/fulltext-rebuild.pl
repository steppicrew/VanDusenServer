#!/usr/bin/perl

use strict;
use warnings;

use PlayFulltext;
use Conf;

use Data::Dumper;

#PlayFulltext::DEBUG(1);

my $fulltext= PlayFulltext->new(CACHE => 1);

my @result= $fulltext->rebuild(0);

print Dumper(\@result), "\n";
