#!/usr/bin/perl

use warnings;
use strict;


#==============================================================================

package Fulltext;

use Carp;
use Data::Dumper;
use DBI;

sub new {
    my $class = shift;
    my $sDbName= shift || "temp.db";

    my $dbh= DBI->connect("dbi:SQLite:dbname=$sDbName", "", "");
    _initDb($dbh);

    bless {
        DBH => $dbh,
    }, $class;
}

sub _initDb {
    my $dbh= shift;
    $dbh->do("CREATE TABLE IF NOT EXISTS keys (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        value TEXT NOT NULL
    )");
    $dbh->do("CREATE TABLE IF NOT EXISTS tris (
        tri TEXT PRIMARY KEY,
        assocs TEXT NOT NULL
    )");
}

sub _tris {
    my $value= shift;

    $value= lc " $value ";      # Spaces at front an end
    $value =~ s/\s+/ /s;        # Unify white space
    my @tris= ();
    my @chars= split(//, $value);
    for (0 .. @chars - 3) {
        push @tris, $chars[$_] . $chars[$_ + 1] . $chars[$_ + 2];
    }
    return @tris;
}

sub _get_tri_assocs {
    my $self= shift;
    my $tri= shift;

    my $sth= $self->{DBH}->prepare_cached("SELECT assocs FROM tris WHERE tri=?");
    $sth->execute($tri);
    my $result= $sth->fetchrow_arrayref();
    $sth->finish();

    # print "**", $result->[0], "**\n";

    return $result ? { split(/:/, $result->[0]) } : undef;
}

sub _set_tri_assocs {
    my $self= shift;
    my $tri= shift;
    my $assocs= shift;

    my $sth= $self->{DBH}->prepare_cached("REPLACE INTO tris (tri, assocs) VALUES (?,?)");
    $sth->execute($tri, join(':', %$assocs));
    $sth->finish();
}

sub _get_key_id_and_values {
    my $self= shift;
    my $key= shift;

    my $sth= $self->{DBH}->prepare_cached("SELECT id, value FROM keys WHERE name=?");
    $sth->execute($key);
    my $result= $sth->fetchrow_arrayref();
    $sth->finish();

    if ($result) {
        my @values= ();
        my $alt= undef;
        for (split(/\t/, $result->[1])) {
            if (defined $alt) {
                push @values, [ $alt, $_ ];
                $alt= undef;
                next;
            }
            $alt= $_;
        }
        return ($result->[0], \@values);
    }

    return undef;
}

sub _get_key_name {
    my $self= shift;
    my $key_id= shift;

    my $sth= $self->{DBH}->prepare_cached("SELECT name FROM keys WHERE id=?");
    $sth->execute($key_id);
    my $result= $sth->fetchrow_arrayref();
    $sth->finish();

    return $result ? $result->[0] : undef;
}

sub _key_values_to_string {
    my $values= shift;

    my @values= ();
    push @values, $_->[0], $_->[1] for @$values;
    return join("\t", @values);
}

sub _add_key {
    my $self= shift;
    my $key= shift;
    my $values= shift;

    my $sth= $self->{DBH}->prepare_cached("INSERT INTO keys (name, value) VALUES (?, ?)");
    $sth->execute($key, _key_values_to_string($values));
    $sth->finish();

    return $self->{DBH}->last_insert_id(undef, undef, undef, undef);
}

sub _update_key_value {
    my $self= shift;
    my $key_id= shift;
    my $values= shift;

    my $sth= $self->{DBH}->prepare_cached("UPDATE keys SET value=? WHERE id=?");
    $sth->execute(_key_values_to_string($values), $key_id);
    $sth->finish();
}

sub _associate {
    my $self = shift;
    my $key_id = shift;
    my $key_values = shift;
    my $remove = shift;

    for (@$key_values) {
        my ($key_value, $weight)= @$_;
        $weight ||= 1;

        for my $tri (_tris($key_value)) {
            my $assocs= $self->_get_tri_assocs($tri) || {};
            if (exists $assocs->{$key_id}) {
                if (!$remove) {
                    $assocs->{$key_id} += $weight;
                }
                else {
                    delete $assocs->{$key_id};
                }
            }
            elsif (!$remove) {
                $assocs->{$key_id}= $weight;
            }
            $self->_set_tri_assocs($tri, $assocs);
        }
    }
}


sub associate {
    my $self = shift;
    my $key = shift;
    my $values = shift;

    $values= [[ $values => 1 ]] unless ref $values;

    my ($key_id, $key_values)= $self->_get_key_id_and_values($key);
    if (defined $key_id) {
        $self->_associate($key_id, $key_values, 1);
        $self->_update_key_value($key_id, $values);
    }
    else {
        $key_id= $self->_add_key($key, $values);
    }

    die "Fulltext::associate: OOPS" unless defined $key_id;

    $self->_associate($key_id, $values);
}

sub getScores {
    my $self= shift;
    my $value= shift;

    my %scores= ();
    for my $tri (_tris(" $value ")) {
        my $assocs= $self->_get_tri_assocs($tri);
        next unless $assocs;
        
        while (my ($key_id, $freq) = each %$assocs) {
            my $key= $self->_get_key_name($key_id);
            unless (exists $scores{$key}) {
                $scores{$key}= 0;
            }
            $scores{$key} += $freq;
        }
    }

    # map {} %scores;

    return %scores;
}

#==============================================================================

package main;

use Data::Dumper;

my $fulltext= new Fulltext;

# $fulltext->associate("first",  [ [ "times" => 1 ], [ "This is the time for all good men" => 3 ] ]);
# $fulltext->associate("second", "Ha Ti Wong");
# $fulltext->associate("third",  "god's messed this one up");
# $fulltext->associate("fourth", "no hit here");

my %scores= $fulltext->getScores("good times");

print Dumper(\%scores), "\n";
