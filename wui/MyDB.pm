#!/usr/bin/perl

package MyDB;

use strict;
use warnings;

use DBI;

sub new {
    my $class= shift;
    my $sDbName= shift;
    my $bReadOnly= shift;

    my $self= {
        name => $sDbName,
        read_only => $bReadOnly,
        dbh => DBI->connect("dbi:SQLite:dbname=$sDbName", "", "", { AutoCommit => 1, ReadOnly => $bReadOnly, }),
        transaction => 0,
        SQL_DEBUG => 0,
    };
    bless $self, $class;
}

sub sth {
    my $self= shift;
    my $sStatement= shift;
    my @sValues= @_;

    $self->__debugQuery($sStatement, @sValues);

    return $self->{dbh}->prepare_cached($sStatement);
}

sub do {
    my $self= shift;
    $self->__debugQuery(@_);

    return $self->{dbh}->do(@_);
}

sub transaction {
    my $self= shift;
    my $fSub= shift;

    return undef if $self->{read_only};

    my $dbh= $self->{dbh};

    $dbh->begin_work() unless $self->{transaction};

    $self->{transaction}++;
    my $result= $fSub->($self);
    $self->{transaction}--;

    if ($result) {
        unless ($self->{transaction}) {
            # if commit failes we have to issue a rollback
            $result= undef unless $dbh->commit();
        }
        return $result if $result;
    }

    print "******** ROLLING BACK TRANSACTION\n";
    $dbh->rollback() unless $self->{transaction};
    return undef;
}

sub getHandle {
    my $self= shift;
    my $sQuery= shift;
    my @sParams= @_;

    my $sth= $self->sth($sQuery, @sParams);
    $sth->execute(@sParams);
    return $sth;
}

sub getHash {
    my $self= shift;
    my $sQuery= shift;
    my @sParams= @_;

    my $sth= $self->getHandle($sQuery, @sParams);
    my $hResult= $sth->fetchrow_hashref();
    $sth->finish();
    return $hResult || {};
}

sub getAllHash {
    my $self= shift;
    my $sQuery= shift;
    my $sIndexKey= shift || '_id';
    my @sParams= @_;

    my $sth= $self->getHandle($sQuery, @sParams);
    return $sth->fetchall_hashref($sIndexKey);
}

sub __hashToArrays {
    my $self= shift;
    my $hash= shift;

    my @fields= ();
    my @values= ();

    map {
        push @fields, $_;
        push @values, $hash->{$_};
    } keys %$hash;
    return (\@fields, \@values);
}

sub __hashToWhereArrays {
    my $self= shift;
    my $hash= shift;

    my @fields= ();
    my @values= ();

    map {
        my $sKey= $_;
        my $sValue= $hash->{$_};
        if (defined $sValue) {
            push @fields, "$sKey=?";
            push @values, $sValue;
        }
        else {
            # fix bug with "null" values
            push @fields, "$sKey is null";
        }
    } keys %$hash;
    return (\@fields, \@values);
}

sub __buildSelectQuery {
    my $self= shift;
    my $hFields= shift;
    my $hWhere= shift;

    my $aTables= [ keys %$hFields ];
    my $aSelectFields= [ map {
        my $sTable= $_;
        if (ref $hFields->{$sTable}) {
            map { "$sTable.$_" } @{$hFields->{$sTable}};
        }
        else {
            $sTable . '.' . $hFields->{$sTable};
        }
    } keys %$hFields ];

    my $sWhere= '';
    my $aValues= [];
    if (defined $hWhere && %$hWhere) {
        $hWhere= { '_id' => $hWhere } unless ref $hWhere;
        my $aFields;
        ($aFields, $aValues)= $self->__hashToWhereArrays($hWhere);
        $sWhere= ' WHERE ' . join(' AND ', @$aFields);
    }

    return ('SELECT _ROWID_, ' . join(', ', @$aSelectFields) . ' FROM ' . join(', ', @$aTables) . $sWhere, @$aValues);
}

sub __debugQuery {
    my $self= shift;
    return unless $self->{SQL_DEBUG};

    my $sQuery= shift;
    my @sValues= @_;

    print "$sQuery with Values ";
    print defined($_) ? "[$_]" : '(undef)' for @sValues;
    print "\n";
}

sub insert {
    my $self= shift;
    my $sTable= shift;
    my $hFields= shift;

    return undef if $self->{read_only};

    my ($aFields, $aValues)= $self->__hashToArrays($hFields);

    my $sQuery= "INSERT INTO $sTable (" . join(', ', @$aFields) . ") VALUES (" . join(', ', map {'?'} @$aValues) . ")";
    my $sth= $self->sth($sQuery, @$aValues);
    unless ($sth->execute(@$aValues)) {
        $sth->finish();
        print "ERROR executing query '$sQuery'\nVALUES:\n", join("\n", @$aValues), "\n";
        return undef;
    }
    $sth->finish();
    $hFields->{_id}= $hFields->{_ROWID_}= $self->{dbh}->last_insert_id("","","","");
    return $hFields;
}

sub update {
    my $self= shift;
    my $sTable= shift;
    my $hFields= shift;
    my $hWhere= shift;

    return undef if $self->{read_only};

    my ($aSetFields, $aSetValues)= $self->__hashToArrays($hFields);

    $hWhere= { '_id' => $hWhere } unless ref $hWhere;
    my ($aWhereFields, $aWhereValues)= $self->__hashToWhereArrays($hWhere);

    my $sQuery= "UPDATE $sTable SET " . join(', ', map {"$_=?"} @$aSetFields) . " WHERE " . join(' AND ', @$aWhereFields);
    my $sth= $self->sth($sQuery, @$aSetValues, @$aWhereValues);
    unless ($sth->execute(@$aSetValues, @$aWhereValues)) {
        print "ERROR executing query '$sQuery'\nVALUES:\n", join("\n", @$aSetValues), "\nWHERE:\n", join("\n", @$aWhereFields), "\n";
        $hFields= undef;
    }
    $sth->finish;
    return $hFields;
}

sub delete {
    my $self= shift;
    my $sTable= shift;
    my $hWhere= shift;

    return undef if $self->{read_only};

    $hWhere= { '_id' => $hWhere } unless ref $hWhere;
    my ($aWhereFields, $aWhereValues)= $self->__hashToWhereArrays($hWhere);

    my $sQuery= "DELETE FROM $sTable WHERE " . join(' AND ', @$aWhereFields);
    my $sth= $self->sth($sQuery, @$aWhereValues);
    my $result= 1;
    unless ($sth->execute(@$aWhereValues)) {
        print "ERROR executing query '$sQuery'\nWHERE:\n", join("\n", @$aWhereValues), "\n";
        $result= undef;
    }
    $sth->finish();
    return $result;
}

sub selectOne {
    my $self= shift;
    my $hFields= shift;
    my $hWhere= shift;

    return $self->getHash($self->__buildSelectQuery($hFields, $hWhere));
}

sub selectAll {
    my $self= shift;
    my $hFields= shift;
    my $hWhere= shift;
    my $sIndexKey= shift;

    my ($sQuery, @values)= $self->__buildSelectQuery($hFields, $hWhere);
    return $self->getAllHash($sQuery, $sIndexKey, @values);
}

sub selectIterator {
    my $self= shift;
    my $hFields= shift;
    my $hWhere= shift;

    my $sth= $self->getHandle($self->__buildSelectQuery($hFields, $hWhere));
    return sub {
        my $hResult= $sth->fetchrow_hashref();
        return $hResult if $hResult;
        $sth->finish();
        return undef;
    };
}

1;

