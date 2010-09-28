package Conf;

use strict;
use warnings;

use Data::Dumper;
use Cwd;

sub new {
    my $class= shift;
    my $sFileName= shift;
    my $hSchema= shift;

    my $fh;
    open $fh, $sFileName or die "Could not open conf file '$sFileName'";
    my $line= 0;
    my %conf= ();
    while (<$fh>) {
        $line++;
        s/^\s+//;
        s/\s+$//;
        next if /^#/;
        next unless /^(\w+?)\s*\=\s*(.*)$/;
        my ($key, $value)= ($1, $2);
        if (exists $hSchema->{$key}) {
            $conf{$key}= ref $hSchema->{$key} ? $hSchema->{$key}->($value) : $value;
            next;
        }
        warn "Unknown key '$key' in line $line";
    }
    close $fh;

    my $self= {
        _conf => \%conf,
        _schema => $hSchema,
    };
    bless $self, $class;
}

sub get {
    my $self= shift;
    my $key= shift;

    return $self->{_conf}{$key} if (exists $self->{_conf}{$key});
    return $self->{_schema}{$key} if (exists $self->{_schema}{$key} && !ref $self->{_schema}{$key});
    warn "You requested an undefined field";
    return undef;
}

sub set {
    my $self= shift;
    my $key= shift;
    my $value= shift;

    $self->{_conf}{$key}= $value;
    return $value;
}

1;
