#!/usr/bin/perl

use strict;
use warnings;

use FileDB;
use Conf;

my %conf= %{Conf::GetConfdata()};
my $fileDb= FileDB->new(%conf);

$fileDb->fixFileLength();
