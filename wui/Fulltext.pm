
package Fulltext;

use warnings;
use strict;

use Carp;
use Data::Dumper;
use DBI;

sub new {
    my $class = shift;
    my $sDbName= shift || "temp.db";
    my %params= @_;

    my $dbh= DBI->connect("dbi:SQLite:dbname=$sDbName", "", "");
    _initDb($dbh);

    my $self= {
        DBH => $dbh,
        CACHE => $params{CACHE},
        PARTS_CACHE => {},
        PARTS_TRANS_CACHE => {},
        TRANSACTION_COUNT => 0,
    };
    
    bless $self, $class;
    
    if ($params{CACHE}) {
        $SIG{'INT'}= sub {
            $SIG{'INT'}= 'IGNORE';
            $self->finish();
            $SIG{'INT'}= 'DEFAULT';
            exit 1;
        };
    }
    
    return $self;
}

sub finish {
    my $self= shift;
    
    $self->{DBH}->rollback() if $self->{TRANSACTION_COUNT};
    $self->{PARTS_TRANS_CACHE}= {};
    $self->{TRANSACTION_COUNT}= 0;

    print "FLUSHING CACHE... PLEASE WAIT...\n";
    $self->{DBH}->begin_work();
    $self->_flush_part_assocs();
    $self->{DBH}->commit();
    print "...DONE\n";
}

sub _initDb {
    my $dbh= shift;
    $dbh->do("CREATE TABLE IF NOT EXISTS keys (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        value TEXT NOT NULL
    )");
    $dbh->do("CREATE INDEX IF NOT EXISTS keys_name ON keys (
        name
    )");
    $dbh->do("CREATE TABLE IF NOT EXISTS parts (
        part TEXT PRIMARY KEY,
        assocs TEXT NOT NULL
    )");
}

sub _beginTransaction {
    my $self= shift;

    return if $self->{TRANSACTION_COUNT}++;
    $self->{DBH}->begin_work();
}

sub _finishTransaction {
    my $self= shift;

    return unless $self->{TRANSACTION_COUNT};
    $self->{TRANSACTION_COUNT}--;
    for my $key (keys %{$self->{PARTS_TRANS_CACHE}}) {
        $self->{PARTS_CACHE}{$key}= $self->{PARTS_TRANS_CACHE}{$key};
    }
    $self->{PARTS_TRANS_CACHE}= {};
    $self->{DBH}->commit();
}

use constant PART_LENGTH => 4;

sub _parts {
    my $value= shift;

    $value= lc " " . substr($value, 0, 1000) . " ";      # Spaces at front and end
    $value =~ s/\s+/ /g;        # Unify white space
    my @parts= ();
    for (0 .. length($value) - PART_LENGTH) {
        push @parts, substr($value, $_, PART_LENGTH);
    }
    return @parts;
}

sub _get_part_assocs {
    my $self= shift;
    my $part= shift;

    my $result= $self->{PARTS_TRANS_CACHE}{$part} || $self->{PARTS_CACHE}{$part};
    return $result if $result;

    my $sth= $self->{DBH}->prepare_cached("SELECT assocs FROM parts WHERE part=?");
    $sth->execute($part);
    $result= $sth->fetchrow_arrayref();
    $sth->finish();

    $result= $result ? { split(/\t/, $result->[0]) } : undef;

    $self->{PARTS_CACHE}{$part}= $result if $self->{CACHE};

    return $result;
}

sub _set_part_assocs {
    my $self= shift;
    my $hAssocs= shift;

    if ($self->{CACHE}) {
        for my $part (keys %$hAssocs) {
            if ($self->{TRANSACTION_COUNT}) {
                $self->{PARTS_TRANS_CACHE}{$part}= $hAssocs->{$part};
            }
            else {
                $self->{PARTS_CACHE}{$part}= $hAssocs->{$part};
            }
        }
        return;
    }
    $self->{PARTS_CACHE}= $hAssocs;
    $self->_flush_part_assocs();
    $self->{PARTS_CACHE}= {};
}

sub _flush_part_assocs {
    my $self= shift;

    my $sth= $self->{DBH}->prepare_cached("REPLACE INTO parts (part, assocs) VALUES (?,?)");

    for my $part (keys %{$self->{PARTS_CACHE}}) {
        $sth->execute($part, join("\t", %{$self->{PARTS_CACHE}{$part}}));
        delete $self->{PARTS_CACHE}{$part};
    }
    $sth->finish();
}

sub _key_values_to_string {
    my $values= shift;

    # print Dumper($values);

    my @values= ();
    push @values, $_->[0], $_->[1] for @$values;
    return join("\t", @values);
}

sub _key_string_to_values {
    my $value= shift;

    my @values= ();
    my $alt= undef;
    for (split(/\t/, $value)) {
        if (defined $alt) {
            push @values, [ $alt, $_ ];
            $alt= undef;
            next;
        }
        $alt= $_;
    }

    return \@values;
}

sub _get_key_id_and_values {
    my $self= shift;
    my $key= shift;

    my $sth= $self->{DBH}->prepare_cached("SELECT id, value FROM keys WHERE name=?");
    $sth->execute($key);
    my $result= $sth->fetchrow_arrayref();
    $sth->finish();

    if ($result) {
        return ($result->[0], _key_string_to_values($result->[1]));
    }

    return undef;
}

sub _get_key_name_and_value {
    my $self= shift;
    my $key_id= shift;

    my $sth= $self->{DBH}->prepare_cached("SELECT name, value FROM keys WHERE id=?");
    $sth->execute($key_id);
    my $result= $sth->fetchrow_arrayref();
    $sth->finish();

    return $result ? ($result->[0], $result->[1]) : undef;
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

sub _min {
    return $_[0] if $_[0] < $_[1];
    return $_[1];
}

# TODO: Alles aus POS_MASK umstellen. ist noch unvollstaendig
use constant POS_MASK => 0x1FF;
use constant POS_LOWBIT => 9;

# So funktioniert's:
# - Rein kommen KeyId und zugehörige KeyValues.
# - Durch die KeyValues wird iteriert.
# - Das KeyValue wird in Parts zerlegt.
# - Pro KeyId/Part wird ein Wert berechnet, der
#   - in den unteren Bits die Wichtung enthält
#   - in den oberen Bits enthält eine Bitmaske enhält, wo ein Bit auf 1 gesetzt wird wenn die Position mit
#     das Part enthält. Und zwar MODULO Anzahl der verfügbaren Bits. Durch das Modulo wird die Information
#     in ein Integer gequetscht mit dem Preis, dass bei den Queries nicht zusammenhängende Parts als
#     zusammenhängend erkannt werden.

sub _associate {
    my $self = shift;
    my $key_id = shift;
    my $key_values = shift;
    my $remove = shift;

    my %assocsCache= ();
    
    for (@$key_values) {
        my ($key_value, $weight)= @$_;
        $weight ||= 1;

        my $pos_bit= -1;
        for my $part (_parts($key_value)) {

            $pos_bit += $pos_bit;
            $pos_bit= POS_MASK + 1 if $pos_bit & 0x80000000;

            $assocsCache{$part}= $self->_get_part_assocs($part) || {} unless exists $assocsCache{$part};

            if (exists $assocsCache{$part}->{$key_id}) {
                if (!$remove) {
                    my $assoc_value= $assocsCache{$part}->{$key_id};
                    $assocsCache{$part}->{$key_id}=
                            _min(($assoc_value & POS_MASK) + $weight, POS_MASK)
                            | ($assoc_value & ~POS_MASK) | $pos_bit;
                }
                else {
                    delete $assocsCache{$part}->{$key_id};
                }
            }
            elsif (!$remove) {
                $assocsCache{$part}->{$key_id}= $weight | $pos_bit;
            }
        }
    }
    $self->_set_part_assocs(\%assocsCache);
}

sub associate {
    my $self = shift;
    my $key = shift;
    my $values = shift;

    $values= [[ $values => 1 ]] unless ref $values;

    $self->_beginTransaction();

    my ($key_id, $key_values)= $self->_get_key_id_and_values($key);

    # print Dumper($values);

    if (defined $key_id) {
        $self->_associate($key_id, $key_values, 1);
        $self->_update_key_value($key_id, $values);
    }
    else {
        $key_id= $self->_add_key($key, $values);
    }

    die "Fulltext::associate: OOPS" unless defined $key_id;

    $self->_associate($key_id, $values);

    $self->_finishTransaction();

}

# Erstellt ein Array mit der Information, welches Folge von 1er Bits
# wie häufig vorkommt (Innerhalb Bits 9 .. 31)
sub _bitogramm {
    my $bits= shift;

    my $pos_bit= POS_MASK + 1;
    my %length;
    my $first_1= 0;
    my $in_1= 0;
    my $i;
    for ($i= POS_LOWBIT; ($bits & $pos_bit) && $i < 31; $i++) {
        $first_1++;
        $pos_bit += $pos_bit;
    }
    for (; $i < 31; $i++) {
        if ($bits & $pos_bit) {
            $in_1++;
        }
        elsif ($in_1) {
            $length{$in_1}++;
            $in_1= 0;
        }
        $pos_bit += $pos_bit;
    }
    $length{$first_1 + $in_1}++;
    return \%length;
}

sub query {
    my $self= shift;
    my $value= shift;
    my $maxResultCount= shift || 1000;

    my %scores= ();
    my @scores= ();
    for my $part (_parts($value)) {
        my $assocs= $self->_get_part_assocs($part);
        next unless $assocs;

        my $keyl= scalar keys %$assocs;

        while (my ($key_id, $weight) = each %$assocs) {
            my ($key, $value)= $self->_get_key_name_and_value($key_id);
            unless (exists $scores{$key}) {
                $scores{$key}= [ ($weight & POS_MASK) / $keyl, $weight & ~POS_MASK ];

# @{ $scores{$key} }[3]= [];

                push @scores, [ $key, _key_string_to_values($value) ];
                next;
            }
            $scores{$key}[0] += ($weight & POS_MASK) / $keyl;
            $scores{$key}[1] |= $weight & ~POS_MASK;

# if ($key_id == 8617 || $key_id == 8611 ) {
#    print STDERR "key_id=$key_id part=$part weight=", sprintf("%08x", $weight & ~POS_MASK), " wweight=",(($weight & POS_MASK) / $keyl), " keyl=$keyl", "\n";
# }
# push @{ $scores{$key}[2] }, $part;
# push @{ $scores{$key}[2] }, $key_id;

        }
    }

# print STDERR Dumper(\$scores{'play:8701'});
# print STDERR Dumper(\$scores{'play:8695'});

    while (my ($key, $value)= each %scores) {
        my $bitogramm= _bitogramm($value->[1]);

        my $result= 0;
        while (my ($key2, $value2)= each %$bitogramm) {
            $result += $key2 * $key2 * $value2;
        }

        $result **= 0.5;

#        $value->[3]= $result;
#        $value->[4]= $value->[0];

        $value->[0] *= $result;

        # print Dumper([ $value->[0], sprintf("%08x", $value->[1] & 0xfffffe00), $bitogramm ]);
    }

#die;


    @scores= sort {
        $scores{$b->[0]}[0] <=> $scores{$a->[0]}[0];
    } @scores;

    @scores= @scores[0 .. $maxResultCount - 1]
        if $maxResultCount && $maxResultCount < @scores;

    return map {
        push @$_
            , $scores{$_->[0]}[0]
#            , $scores{$_->[0]}[4]
#            , sprintf("%08x", $scores{$_->[0]}[1])
#            , $scores{$_->[0]}[2]
#            , $scores{$_->[0]}[3]
#            , _bitogramm($scores{$_->[0]}[1])
        ;
        $_
    } @scores;
}

1;
