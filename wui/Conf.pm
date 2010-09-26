package Conf;

use strict;
use warnings;

use Data::Dumper;
use Cwd;

my $sConfFileName= './wui.conf';
my %conf= (
    # timeout 1 jahr
    timeout => 365 * 86_500,
);

{
    my $fh;
    open $fh, $sConfFileName or die "Could not open conf file '$sConfFileName'";
    my %fConfSets= (
        basedir    => sub { $conf{basedir}=    Cwd::abs_path(shift); $conf{basedir}=~ s/\/$//; },
        mp3url     => sub { $conf{mp3url}=     shift; },
        oggurl     => sub { $conf{oggurl}=     shift; },
        md5db      => sub { $conf{md5db}=      shift; },
        hoerdatdb  => sub { $conf{hoerdatdb}=  shift; },
        fulltextdb => sub { $conf{fulltextdb}= shift; },
        timeout    => sub { $conf{timeout}=    shift; },
        readonly   => sub { $conf{readonly}=   shift; },
    );
    my $line= 0;
    while (<$fh>) {
        $line++;
        s/^\s+//;
        s/\s+$//;
        next if /^#/;
        next unless /^(\w+?)\s*\=\s*(.*)$/;
        my ($key, $value)= ($1, $2);
        if ($fConfSets{$key}) {
            $fConfSets{$key}->($value);
            next;
        }
        warn "Unknown key '$key' in line $line";
    }
    close $fh;
}

sub GetConfdata {
    my $class= shift;

    return { %conf };
}

1;
