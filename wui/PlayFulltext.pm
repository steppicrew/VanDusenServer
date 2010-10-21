
package PlayFulltext;

use strict;
use warnings;

use Fulltext;
use FileDB;
use Conf;

use Data::Dumper;

our $DEBUG= 0;

sub DEBUG { $DEBUG= $_[0]; }

my %weights= (
    titles => 4,
    authors => 2,
    genres => 2,
    description => 1,
    stations => 1,
    directors => 1,
);

sub new {
    my $class = shift;
    my @params= @_;

#    my %conf= %{Conf->GetConfdata()};
    my $conf= Conf->new(
        './wui.conf',
        {
            basedir    => sub { my $v= Cwd::abs_path(shift); $v=~ s/\/$//; $v },
            mp3url     => undef,
            oggurl     => undef,
            md5db      => undef,
            hoerdatdb  => undef,
            fulltextdb => undef,
            timeout    => undef,
            readonly   => undef,
            timeout    => 31_536_000,
        }
    );

    my $fileDb;
    
    my $self= {
        FULLTEXT => Fulltext->new($conf->get('fulltextdb'), @params),
        FN_FILEDB => sub {
            $fileDb= FileDB->new($conf) unless $fileDb;
            return $fileDb;
        },
        conf => $conf,
    };

    bless $self, $class;
}

sub rebuild {
    my $self= shift;
    my $startPlayId= shift || 0;

    my $dbFile= $self->{FN_FILEDB}->();

    my $aPlayIds= $dbFile->getAllPlayIds();

    my $debug_i= 100 if $DEBUG;

    for my $iPlayId (@$aPlayIds) {

        next if $iPlayId < $startPlayId;

        return if $DEBUG && $debug_i-- <= 0;

        my $hPlayDetails= $dbFile->getPlayDetails($iPlayId);
        $self->associate('play', $iPlayId, $hPlayDetails);
        print "$iPlayId: $hPlayDetails->{titles}[0]\n";
    }
    my $aMd5= $dbFile->getAllFilesWOPlay();
    
    $debug_i= 100 if $DEBUG;

    for my $sMd5 (@$aMd5) {

        return if $DEBUG && $debug_i-- <= 0;

        my $hFileDetails= $dbFile->getFileDetails($sMd5);
        next unless $hFileDetails->{name} =~ /\.mp.$/;
        $self->associate('file', $sMd5, $hFileDetails->{'.guessed'});
        print "$sMd5: " . $hFileDetails->{name} . "\n";
    }
    $self->{FULLTEXT}->finish();
}

sub associate {
    my $self= shift;
    my $sType= shift;
    my $sId= shift;
    my $hData= shift;

    my $fulltext= $self->{FULLTEXT};

    $hData->{authors}= [ map {
        my @name= ();
        push @name, $_->{given_name} if $_->{given_name};
        push @name, $_->{name} if $_->{name};
        join(' ', @name);
    } @{$hData->{authors}} ] if $hData->{authors};
    $hData->{roles}= [ %{$hData->{roles}} ] if $hData->{roles};

    my @params= ();
    for my $field (sort keys %weights) {
        my $value= $hData->{$field};
        $value= '' unless defined $value;
        $value= join(' ', @$value) if ref $value;
        push @params, [ $value => $weights{$field} ];
    }
    $fulltext->associate("$sType:$sId", \@params);
}

# TODO: 10 Ergebnisse hardgecoded. OK?
# TODO: nach Fulltext.pm?
sub _query {
    my $self= shift;
    my $value= shift;
    my $maxResultCount= shift || 10;

    my $fulltext= $self->{FULLTEXT};
    my @results= $fulltext->query($value, $maxResultCount);

    for (@results) {
        my $result_values= $_->[1];
        my %values;
        my $i= 0;
        for (sort keys %weights) {
            $values{$_}= $result_values->[$i++][0];
        }
        $_->[1]= \%values;
    }
    return @results;
}

sub query {
    my $self= shift;
    my $value= shift;
    my $maxResultCount= shift || 10;

    my $dbFile= $self->{FN_FILEDB}->();

    my @results= $self->_query($value, $maxResultCount);
    my @items= ();
    my $iSortPos= 1;
    for my $result (@results) {
        my $iScore= $result->[2];
        my ($sType, $iId)= split /\:/, $result->[0], 2;
        my $hDetails;
        if ($sType eq 'play') {
            $hDetails= $dbFile->getPlayDetails($iId);
        }
        elsif ($sType eq 'file') {
            $hDetails= $dbFile->getFileDetails($iId);
        }
        else {
            print "No such type: '$sType'\n";
            next;
        }
        $hDetails->{'search_score'}= $iScore;
        $hDetails->{'sort_pos'}= $iSortPos++;
        push @items, $hDetails;
    }
    return @items;
}

1;
