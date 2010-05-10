#!/usr/bin/perl

package ParseHoerdat;

use strict;
use URI::Escape;
use HTTP::Request;
use LWP::UserAgent;
use HTML::TreeBuilder;
use Encode;
use Data::Dumper;

use Carp ();
$SIG{__WARN__} = \&Carp::cluck;
$SIG{__DIE__} = \&Carp::cluck;

use Data::Dumper;

# timeout for http-requests
my $iHttpTimeout= 10;

my %FieldMap= (
    title => 'ti',
    author_name => 'au.an',
    author_given_name => 'au.av',
);

my %ParseMap= (
    'auch unter dem titel'
                    => sub { { 'other_titles' => __parseList(shift) } },
    'autor'         => sub { { 'authors'      => __parseAuthors(__parseList(shift)) } },
    'bearbeiter'    => sub { { 'arrangers'    => __parseList(shift) } },
    'genre'         => sub { { 'genres'       => __parseList(shift) } },
    'inhaltsangabe' => sub { { 'description'  => join "\n", @{__parseList(shift)} } },
    'links'         => sub { __parseLinks(shift) },
    'mitwirkende'   => sub { { 'roles'        => __parseRoles(__parseList(shift)) } },
    'produktion'    => sub { __parseProduction(__parseScalar(shift)) },
    'regisseur'     => sub { { 'directors'    => __parseList(shift) } },
    'schlagwörter'  => sub { { 'keywords'     => __parseList(shift) } },
);

my $sHoerdatBase= 'http://www.hoerdat.in-berlin.de/select.php';

sub new {
    my $class= shift;
    my $hQuery= shift;

    my $self= {
        query_data => $hQuery,
    };
    bless $self, $class;
}

sub query {
    my $self= shift;
    
    my $num= 0;
    my @letter= ('a'..'z');

    my %query_data= (%{$self->{query_data}});
    # remove title parts "XXX: "
    $query_data{title}=~ s/^(.+)\:\s*// if $query_data{title};
    # remove title parts "..."
    $query_data{title}=~ s/\.+\s*$// if $query_data{title};

    # filter out empty fields
    my %query= map {
        uri_escape(decode("utf8", $_))
    } map {
        my $letter= $letter[$num++];
        (
            $letter => $query_data{$_},
            "col$num" => $FieldMap{$_},
            "bool$num" => 'and',
        )
    } grep { $FieldMap{$_} && $query_data{$_} } keys %query_data;
    return [] unless %query;

    my $sQuery= "$sHoerdatBase?" . join '&', map { "$_=$query{$_}" } keys %query;

    print "Requesting: $sQuery\n";

    my $request= HTTP::Request->new(GET => $sQuery);
    my $ua= LWP::UserAgent->new();
    $ua->timeout($iHttpTimeout);
    my $response= $ua->request($request);
#    my $sCharset= $1 if $response->header('content-type')=~ /charset\=([\-\w]+)/;
#    print "CT: $sCharset\n";
    return $self->_parse(encode("utf8", $response->decoded_content));
}

sub _parse {
    my $self= shift;
    my $sContent= shift;
    
    my $tree= HTML::TreeBuilder->new_from_content($sContent);
    
    return [ map { $self->_parseTable($_) } $tree->look_down('_tag', 'table') ];
}

sub _parseTable {
    my $self= shift;
    my $table= shift;
    
    my %result= (type => 'play');
    
    my @lines= $table->look_down('_tag', 'tr');

    for my $line (@lines) {
        # scan for title
        my $title= $line->look_down('_tag', 'th');
        if ($title) {
            $result{'titles'}= [__chomp($title->as_text())];
            next;
        }
        my @cells= $line->look_down('_tag', 'td');
        next unless scalar @cells > 1;
        
        my $sKey= lc __chomp($cells[0]->as_text());
        $sKey=~ s/\:$//;
        $sKey=~ s/\(\w+\)$//;
#        $self->_chomp($cells[1]->as_text());
        if ($ParseMap{$sKey}) {
            my $hResult= $ParseMap{$sKey}->($cells[1]);
            @result{keys %$hResult}= values %$hResult;
        }
    }
    if ($result{'other_titles'}) {
        push @{$result{'titles'}}, @{$result{'other_titles'}};
        delete $result{'other_titles'};
    }
        
#    print Dumper(\%result);

    return \%result;
}


#########################################
## parsing
#########################################

sub __chomp {
    my $sText= shift;
    
    $sText=~ s/\s\s+/ /g;
    $sText=~ s/^\s+//;
    $sText=~ s/\s+$//;
    return $sText;
}

sub __parseList {
    my $sIn= shift;
    my @list= ('');
    
    for my $elem ($sIn->content_list()) {
        if (ref $elem) {
            if ($elem->tag() eq 'br') {
                push @list, '';
                next;
            }
            $list[-1].= $elem->as_text();
            next;
        }
        $list[-1].= $elem;
    }
    
    
    return [ grep { $_ ne '' } map { __chomp($_) } @list ];
}

sub __parseScalar {
    my $sIn= shift;
    return __chomp($sIn->as_text());
}

sub __parseAuthors {
    my $sNames= shift;
    my $aAuthors= [];
    for my $sName (@$sNames) {
        $sName=~ s/\(.*\)//;
        $sName= __chomp($sName);
        next if $sName eq '';
        my $sGivenName= $1 if $sName=~ s/^(.+)\s(\w+)/$2/;
        push @$aAuthors, {
            name => $sName,
            given_name => $sGivenName,
        };
    }
    return $aAuthors;
}

sub __parseRoles {
    my $aRoles= shift;
    
    my $hRoles= {};
    for my $sArtist (@$aRoles) {
        my $sRole=__chomp($1) if $sArtist=~ s/^(.*\S?)\:\s+//;
        if ($sRole) {
            $hRoles->{$sRole}= __chomp($sArtist);
            next;
        }
        $hRoles->{''}= [] unless $hRoles->{''};
        push @{$hRoles->{''}}, map { __chomp($_) } split /\,/, $sArtist;
    }
    return $hRoles;
}

sub __parseProduction {
    my $sProduction= shift;
    my $sStations= $1 if $sProduction=~ s/^([\w\/]+)\s+(\d+)\s+/$2 /;
    my $iYear= $1 if $sProduction=~ s/^(\d+)\s+//;
    return {
        stations => [ $sStations ? split /\//, $sStations : () ],
        year => $iYear,
    };
}

sub __parseLinks {
    my $links= shift;
    for my $link ($links->look_down('_tag', 'a')) {
        my $sHref= $link->attr('href');
        next unless $sHref;
        return {
            'hoerdat_id' => $1
        } if $sHref=~ /\bn\=(\d+)\b/;
        $sHref= $link->as_HTML();
        # correct bug in hoerdat result (if there is a "'" in authors name it isn't escaped)
        return {
            'hoerdat_id' => $1
        } if $sHref=~ /\bn\=\"?(\d+)\b/;
    }
    return {};
}

1;

