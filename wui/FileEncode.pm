#!/usr/bin/perl

package FileEncode;

use warnings;
use strict;

use Symbol qw(gensym);
use HTTP::Response;

use File::Spec;
use URI::Escape;
use Digest::MD5 qw(md5_hex);
use POSIX;
use Cwd 'abs_path';

use Data::Dumper;

sub new {
    my $class= shift;
    my $conf= shift;

    my $self= {
        conf => $conf,
    };

    bless $self, $class;
}

sub encode {
    my $self= shift;
    my $params= shift;

    my $sInFileName= uri_unescape($params->{'filename'});
    my $sFormat= $params->{'format'};

    my $sBasePath= $self->{conf}->get('basedir');
    $sBasePath=~ s/\/*$//;
    my $q_sBasePath= quotemeta $sBasePath;

    $sInFileName= abs_path "$sBasePath/$sInFileName";
    my $sRelInFileName= $sInFileName;
    $sRelInFileName=~ s/^$q_sBasePath\//\//;

    my $sOutFileName= $self->buildOutFileName($sRelInFileName);
    my $sRelOutFileName= $sOutFileName;
    $sRelOutFileName=~ s/^$q_sBasePath\//\//;

    my $isEncoding= -f $sOutFileName ? 0 : 1;

    if (!$isEncoding) {
        utime time, time, $sOutFileName
    }
    else {
        $self->cleanupDir();
        my $sTempFileName= "$sOutFileName.tmp";
        unlink $sTempFileName if -f $sTempFileName;
        my $cmd= $self->buildTheoraCommand($sInFileName, $sOutFileName);
        system "$cmd &";
        sleep 3;
    }

    print "play file '$sRelOutFileName'\n";

    return {
        path => $sRelOutFileName,
        encoding => $isEncoding,
    }
}

sub buildOutFileName {
    my $self= shift;
    my $reqFile= shift;
    return File::Spec->catfile($self->{conf}->get('encode_tempdir'), md5_hex($reqFile) . '.oga');
}

sub buildTheoraCommand {
    my $self= shift;
    my $sFile= shift || '';
    my $sOutFile= shift || 'tmp';
    my $sTmpFile= "$sOutFile.tmp";
    $sFile=~ s/\\/\\\\/g;
    $sFile=~ s/\"/\\\"/g;
    return 'ffmpeg2theora --novideo --output "' . $sTmpFile . '" "' . $sFile . '" && mv "' . $sTmpFile . '" "' . $sOutFile . '"';
}

sub cleanupDir {
    my $self= shift;
    # read temp dir and delete oldest files if more than configured in "tempcount"
    my $dh;
    my $dir= $self->{conf}->get('encode_tempdir');
    opendir($dh, $dir) or die "Temp dir '$dir' does not exist!";
    my %files= map { (stat)[9] => $_ } grep { -f } map { "$dir/$_" } readdir $dh;
    closedir $dh;
    my @keys= sort {$b <=> $a} keys %files;
    splice @keys, 0, $self->{conf}->get('encode_tempcount');
    unlink $files{$_} for (@keys);
}

1;
