#!/usr/bin/perl

package FileDB;

use strict;
use warnings;
use Digest::MD5;
use File::Spec;
use Data::Dumper;
use PlayFulltext;
use MP3::Info;
use MyDB;

sub new {
    my $class= shift;
    my $conf= shift;

    my $sHoerdatDb= $conf->get('hoerdatdb');
    my $sMd5Db= $conf->get('md5db');
    my $sBaseDir= $conf->get('basedir');
    my $bReadOnly= $conf->get('readonly');

    die "FileDB: Need at least 'hoerdatdb', 'md5db' and 'basedir' in constructor" unless $sHoerdatDb && $sMd5Db && defined $sBaseDir;

    my $fulltext;

    my $self= {
        db => {
            hoerdat => MyDB->new($sHoerdatDb, $bReadOnly),
            md5     => MyDB->new($sMd5Db, 1),
        },
        fn_fulltext => sub {
            $fulltext= new PlayFulltext() unless $fulltext;
            return $fulltext;
        },
        basedir => $sBaseDir,
    };
    bless $self, $class;

    $self->__initTables();

    return $self;
}

# TODO: move some where else
sub NumSort {
    my $self= shift;
    my $fn_key= shift;
    my @data= @_;

    my $hData= {};
    for my $data (@data) {
        my $key= lc $fn_key->($data);
        my $fn= sub {
            my $digits= shift;
            $digits=~ s/^0+(\d)/$1/;
            return 100000 + $digits;
        };
        $key=~ s/(\d{1,5})/$fn->($1)/ge;
        $hData->{$key}= [] unless $hData->{$key};
        push @{$hData->{$key}}, $data;
    }

    return map { @{$hData->{$_}} } sort keys %{$hData};
}

sub _db_transaction {
    my $self= shift;
    my $sDb= shift;
    my $fn= shift;

    return $self->{db}{$sDb}->transaction($fn);
}

sub __initTables {
    my $self= shift;

    return if $self->{readonly};

    $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        $db->do('
            CREATE TABLE IF NOT EXISTS files (
                md5 TEXT PRIMARY KEY NOT NULL,
                addition TEXT,
                part_count INTEGER,
                part_num INTEGER,
                play_id INTEGER NOT NULL,
                quality INTEGER,
                last_played INTEGER,
                play_order INTEGER,
                length INTEGER
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS plays (
                _id INTEGER PRIMARY KEY,
                audio INTEGER,
                description TEXT,
                hoerdat_id INTEGER UNIQUE,
                rating INTEGER,
                title_id INTEGER NOT NULL,
                year INTEGER
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS titles (
                _id INTEGER PRIMARY KEY,
                play_id INTEGER NOT NULL,
                title TEXT
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS authors (
                _id INTEGER PRIMARY KEY,
                given_name TEXT,
                name TEXT NOT NULL
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS play_author (
                play_id INTEGER,
                author_id INTEGER,
                PRIMARY KEY (play_id, author_id)
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS genres (
                _id INTEGER PRIMARY KEY,
                genre TEXT NOT NULL
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS play_genre (
                genre_id INTEGER NOT NULL,
                play_id INTEGER NOT NULL,
                PRIMARY KEY (play_id, genre_id)
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS keywords (
                _id INTEGER PRIMARY KEY,
                keyword TEXT NOT NULL
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS play_keyword (
                keyword_id INTEGER NOT NULL,
                play_id INTEGER NOT NULL,
                PRIMARY KEY (play_id, keyword_id)
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS stations (
                _id INTEGER PRIMARY KEY,
                station TEXT NOT NULL
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS play_station (
                play_id INTEGER NOT NULL,
                station_id INTEGER NOT NULL,
                PRIMARY KEY (play_id, station_id)
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS names (
                _id INTEGER PRIMARY KEY,
                name TEXT NOT NULL
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS play_arranger (
                play_id INTEGER NOT NULL,
                arranger_id INTEGER NOT NULL,
                PRIMARY KEY (play_id, arranger_id)
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS play_director (
                play_id INTEGER NOT NULL,
                director_id INTEGER NOT NULL,
                PRIMARY KEY (play_id, director_id)
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS roles (
                _id INTEGER PRIMARY KEY,
                artist_id INTEGER NOT NULL,
                play_id INTEGER NOT NULL,
                role TEXT
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS playlists (
                _id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE
            )
        ');
        $db->do('
            CREATE TABLE IF NOT EXISTS playlist_play (
                playlist_id INTEGER NOT NULL,
                play_id INTEGER NOT NULL,
                sort_pos INTEGER NOT NULL,
                random_pos TEXT,
                PRIMARY KEY (playlist_id, play_id)
            )
        ');
        $db->do('CREATE INDEX IF NOT EXISTS files_play         ON files         ( play_id )');
        $db->do('CREATE INDEX IF NOT EXISTS play_arranger_play ON play_arranger ( play_id )');
        $db->do('CREATE INDEX IF NOT EXISTS play_author_play   ON play_author   ( play_id )');
        $db->do('CREATE INDEX IF NOT EXISTS play_director_play ON play_director ( play_id )');
        $db->do('CREATE INDEX IF NOT EXISTS play_genre_play    ON play_genre    ( play_id )');
        $db->do('CREATE INDEX IF NOT EXISTS play_keyword_play  ON play_keyword  ( play_id )');
        $db->do('CREATE INDEX IF NOT EXISTS play_station_play  ON play_station  ( play_id )');
        $db->do('CREATE INDEX IF NOT EXISTS authors_name       ON authors       ( name, given_name )');
        $db->do('CREATE INDEX IF NOT EXISTS roles_play_artist  ON roles         ( play_id, artist_id )');
        $db->do('CREATE INDEX IF NOT EXISTS titles_play        ON titles        ( play_id )');
    });

    $self->_db_transaction('md5', sub {
        my $db= shift;
        $db->do('
            CREATE TABLE IF NOT EXISTS files (
                path text not null,
                name test not null,
                size integer not null,
                md5 text not null,
                date integer
            )
        ');
        $db->do('CREATE INDEX IF NOT EXISTS file_md5           ON files     ( md5 )');
        $db->do('CREATE INDEX IF NOT EXISTS file_path          ON files     ( path )');
        $db->do('CREATE INDEX IF NOT EXISTS file_path_name     ON files     ( path, name )');
        $db->do('CREATE INDEX IF NOT EXISTS file_size          ON files     ( size )');
        return 1;
    });
};

sub getFileParam {
    my $self= shift;
    my $param= shift;
    return @$param if ref $param eq 'ARRAY';
    return $self->splitFile($param);
}

sub joinFile {
    my $self= shift;
    return File::Spec->canonpath(File::Spec->catpath(undef, shift, shift));
}

sub splitFile {
    my $self= shift;
    my (undef, $sDir, $sFile)= File::Spec->splitpath(shift);
    our $sqBaseDir= quotemeta $self->{basedir};
    $sDir= "/$sDir" unless $sDir=~/^\//;
    $sDir=~ s/^$sqBaseDir//;
    return ($sDir, $sFile);
}

sub localFile {
    my $self= shift;
    my ($sDir, $sFile)= $self->getFileParam(shift);
    return $self->joinFile("$self->{basedir}/$sDir", $sFile);
}

sub __cleanupDB {
    my $self= shift;

    return undef if $self->{readonly};

    my @sQueries= (
        "DELETE FROM plays WHERE _id NOT IN (SELECT DISTINCT play_id FROM files)",
        "DELETE FROM titles WHERE play_id NOT IN (SELECT _id FROM plays)",
        "DELETE FROM roles WHERE play_id NOT IN (SELECT _id FROM plays)",
        "DELETE FROM playlist_play WHERE play_id NOT IN (SELECT _id FROM plays)",
    );
    for my $sTable ('arranger', 'author', 'director', 'genre', 'keyword', 'station') {
        push @sQueries, "DELETE FROM play_$sTable WHERE play_id NOT IN (SELECT _id FROM plays)";
    }
    push @sQueries, "DELETE FROM authors WHERE _id NOT IN (SELECT DISTINCT author_id FROM play_author)";

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        for my $sQuery (@sQueries) {
            my $sth= $db->sth($sQuery);
            return unless $sth->execute();
            $sth->finish();
        }
        return 1;
    });
}

sub _calcMd5 {
    my $self= shift;
    my ($sDir, $sFile)= $self->getFileParam(shift);
    my $sFileName= $self->localFile([$sDir, $sFile]);
    my $fh;
    return undef unless -f $sFileName && open $fh, "<$sFileName";
    my $md5= Digest::MD5->new();
    $md5->addfile($fh);
    close $fh;
    return $self->insertMd5([$sDir, $sFile], $md5->hexdigest);
}

sub insertMd5 {
    my $self= shift;
    my ($sDir, $sFile)= $self->getFileParam(shift);
    my $sFileName= $self->localFile([$sDir, $sFile]);
    my $sMd5= shift;
    my (undef, undef, undef, undef, undef, undef, undef, $size, undef, $mtime)= stat($sFileName);

    return $self->_db_transaction('md5', sub {
        my $db= shift;
        return unless $db->insert('files', {
            path => $sDir,
            name => $sFile,
            md5 => $sMd5,
            size => $size,
            date => $mtime,
        });
        return $sMd5;
    });
}

sub _mp3Length {
    my $self= shift;
    my ($sDir, $sFile)= $self->getFileParam(shift);
    my $sFileName= $self->localFile([$sDir, $sFile]);
    return undef unless -f $sFileName;
    my $info= get_mp3info($sFileName);
    return int ($info->{SECS} || 0);
}

sub _mp3LengthByMd5 {
    my $self= shift;
    my $sMd5= shift;

    my $hFile= $self->{db}{md5}->selectOne({files => '*'}, {md5 => $sMd5});
    return undef unless $hFile;
    return $self->_mp3Length([$hFile->{path}, $hFile->{name}]);
}

sub _mergeFileName {
    my $self= shift;
    my $hFileData= shift;
    my $sMd5= shift || $hFileData->{md5};

    $hFileData->{md5}= $sMd5 unless scalar %$hFileData;

    my $hMd5Data= $self->{db}{md5}->selectOne({files => '*'}, {md5 => $hFileData->{md5}});
    $hFileData->{name}= $hMd5Data->{name};
    $hFileData->{dir}= $hMd5Data->{path};
    return $hFileData;
}

sub _getFileDataByMd5 {
    my $self= shift;
    my $sMd5= shift;

    return $self->_mergeFileName($self->{db}{hoerdat}->selectOne({files => '*'}, {md5 => $sMd5}), $sMd5);
}

sub _getPlayData {
    my $self= shift;
    my $hWhere= shift;

    $hWhere= { '_id' => $hWhere } unless ref $hWhere;
    my @fields= ();
    my @values= ();

    map {
        push @fields, $_;
        push @values, $hWhere->{$_};
    } keys %$hWhere;

    return $self->{db}{hoerdat}->selectOne({plays => '*'}, $hWhere);
}

sub _getPlayTitles {
    my $self= shift;
    my $iPlayId= shift;
    my $iTitleId= shift;

    return undef unless $iPlayId > 0;

    my $hTitles= $self->{db}{hoerdat}->selectAll({titles => '*'}, {play_id => $iPlayId});
    return undef unless %$hTitles;

    my $aTitles= [ map { $hTitles->{$_}{title} } grep { $_ != $iTitleId } keys %$hTitles ];
    unshift @$aTitles, $hTitles->{$iTitleId}{title} if $hTitles->{$iTitleId} && defined $hTitles->{$iTitleId}{title};

    return undef unless @$aTitles;
    return $aTitles;
}

sub _getPlayStations {
    my $self= shift;
    my $iPlayId= shift;

    return undef unless $iPlayId > 0;
    my $hStations= $self->{db}{hoerdat}->getAllHash(
        'SELECT stations.* FROM stations JOIN play_station ON stations._id = play_station.station_id WHERE play_station.play_id=?',
        undef,
        $iPlayId,
    );
    return undef unless %$hStations;
    return [ sort map {$hStations->{$_}{station}} keys %$hStations ];
}

sub _getPlayAuthors {
    my $self= shift;
    my $iPlayId= shift;

    return undef unless $iPlayId > 0;
    my $hAuthors= $self->{db}{hoerdat}->getAllHash(
        'SELECT authors.* FROM authors JOIN play_author ON authors._id = play_author.author_id WHERE play_author.play_id=?',
        undef,
        $iPlayId,
    );
    return undef unless %$hAuthors;
    return [ sort map { { name => $hAuthors->{$_}{name}, given_name => $hAuthors->{$_}{given_name} } } keys %$hAuthors ];
}

sub _getPlayNames {
    my $self= shift;
    my $sName= shift;
    my $iPlayId= shift;

    return undef unless $iPlayId > 0;
    my $sCross= 'play_' . $sName;
    my $sRefField= "$sCross.${sName}_id";
    my $hNames= $self->{db}{hoerdat}->getAllHash(
        "SELECT names.* FROM names JOIN $sCross ON names._id = $sRefField WHERE $sCross.play_id=?",
        undef,
        $iPlayId,
    );
    return undef unless %$hNames;
    return [ map {$hNames->{$_}{name}} keys %$hNames ];
}

sub _getPlayKeywords {
    my $self= shift;
    my $iPlayId= shift;

    return undef unless $iPlayId > 0;
    my $hKeywords= $self->{db}{hoerdat}->getAllHash(
        'SELECT keywords.* FROM keywords JOIN play_keyword ON keywords._id = play_keyword.keyword_id WHERE play_keyword.play_id=?',
        undef,
        $iPlayId,
    );
    return undef unless %$hKeywords;
    return [ map {$hKeywords->{$_}{keyword}} keys %$hKeywords ];
}

sub _getPlayGenres {
    my $self= shift;
    my $iPlayId= shift;

    return undef unless $iPlayId > 0;
    my $hGenres= $self->{db}{hoerdat}->getAllHash(
        'SELECT genres.* FROM genres JOIN play_genre ON genres._id = play_genre.genre_id WHERE play_genre.play_id=?',
        undef,
        $iPlayId,
    );
    return undef unless %$hGenres;
    return [ map {$hGenres->{$_}{genre}} keys %$hGenres ];
}

sub _getPlayRoles {
    my $self= shift;
    my $iPlayId= shift;

    return undef unless $iPlayId > 0;

    my $hResult= {};

    my $hRoles= $self->{db}{hoerdat}->getAllHash(
        'SELECT roles.*, names.name FROM roles JOIN names ON names._id = roles.artist_id WHERE roles.play_id=?',
        undef,
        $iPlayId,
    );
    return undef unless %$hRoles;
    map {
        my $sRole= $hRoles->{$_}{role};
        if ($sRole) {
            $hResult->{$sRole}= $hRoles->{$_}{name};
        }
        else {
            $hResult->{''}= [] unless $hResult->{''};
            push @{$hResult->{''}}, $hRoles->{$_}{name};
        }
    } keys %$hRoles;
    return $hResult;
}

sub _parseFileName {
    my $self= shift;
    my $sFileName= shift;
    my $hResult= {};

    return $hResult unless defined $sFileName;

    $sFileName=~ s/\.mp.$//i;

    if ($sFileName=~ /^\s*(.+?)\s*_\s*(.+)\s*_\s*(.+)\s*$/ || $sFileName=~ /^\s*(.+?)\s*\-\s*(.+)\s*\-\s*(.+)\s*$/) {
        my ($sAuthorName, $sTitle, $sStations)= ($1, $2, $3);
        ($hResult->{part_num}, $hResult->{part_count})= ($1, $2) if $sTitle=~ s/\s+(\d+)v(\d+)$//i;
#        $hResult->{addition}= $1 if $sTitle=~ s/\s*\(\s*(.+)\s*\)\s*$//;
        $sTitle=~ s/\s*\(\s*(.+)\s*\)\s*$//;
        $hResult->{titles}= [$sTitle];
        my $sAuthorGivenName= $1 if $sAuthorName=~ s/\,\s*(.+)$// || $sAuthorName=~ s/^(\w+)\s+//;
        $hResult->{authors}= [ { name => $sAuthorName, given_name => $sAuthorGivenName, } ];
        $hResult->{year}= $1 if $sStations=~ s/\b(\d{4})\b//;
        $hResult->{stations}= [ grep {$_} split /\s*\,\s*/, $1 ] if $sStations=~ /(\w[\w\,\s]*\w)/;
    }

    return $hResult;
}

sub _updateTitles {
    my $self= shift;
    my $iPlayId= shift;
    my $aTitles= shift || [];

    return undef if $iPlayId < 0 || scalar @$aTitles == 0;

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        my $hTitles= $db->selectAll({titles => '*'}, {play_id => $iPlayId});
        my $iMainTitleId;
        $aTitles= [ map { s/\s+/ /g; $_; } @$aTitles ];
        my $sMainTitle= shift @$aTitles;
        for my $iTitleId (keys %$hTitles) {
            my $hTitle= $hTitles->{$iTitleId};
            if ($hTitle->{title} eq $sMainTitle) {
                $iMainTitleId= $hTitle->{_id};
                delete $hTitles->{$iTitleId};
                last;
            }
        }
        unless ($iMainTitleId) {
            my $hNewTitle= $db->insert('titles', {play_id => $iPlayId, 'title' => $sMainTitle});
            $iMainTitleId= $hNewTitle->{_id};
        }
        for my $sTitle (@$aTitles) {
            my $bFound= 0;
            for my $iTitleId (keys %$hTitles) {
                my $hTitle= $hTitles->{$iTitleId};
                if ($hTitle->{title} eq $sTitle) {
                    delete $hTitles->{$iTitleId};
                    $bFound= 1;
                }
            }
            unless ($bFound) {
                return unless $db->insert('titles', {play_id => $iPlayId, 'title' => $sTitle});
            }
        }
        for my $iTitleId (keys %$hTitles) {
            $db->delete('titles', {play_id => $iPlayId, _id => $iTitleId});
        }
        return $iMainTitleId;
    });
}

sub _updateAuthors {
    my $self= shift;
    my $iPlayId= shift;
    my $aAuthors= shift || [];

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        return unless $db->delete('play_author', {play_id => $iPlayId});
        my %hAuthorIds= ();
        for my $hAuthor (@$aAuthors) {
            my $hAuthorData= $db->selectOne({authors => '*'}, {name => $hAuthor->{name}, given_name => $hAuthor->{given_name}});
            $hAuthorData= $db->insert('authors', {name => $hAuthor->{name}, given_name => $hAuthor->{given_name}}) unless %$hAuthorData;
            return unless $hAuthorData;

            next if $hAuthorIds{$hAuthorData->{_id}};
            $hAuthorIds{$hAuthorData->{_id}}= 1;

            return unless $db->insert('play_author', {play_id => $iPlayId, author_id => $hAuthorData->{_id}});
        }
        return 1;
    });
}

sub _updateManyToMany {
    my $self= shift;
    my $sCrossTable= shift;     # play_station
    my $sCrossId= shift;        # station_id
    my $sTable= shift;          # stations
    my $sField= shift;          # station
    my $iPlayId= shift;
    my $aValues= shift || [];

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        return unless $db->delete($sCrossTable, {play_id => $iPlayId});
        my %hCrossIds= ();
        for my $sValue (@$aValues) {
            my $hData= $db->selectOne({$sTable => '*'}, {$sField => $sValue});
            $hData= $db->insert($sTable, {$sField => $sValue}) unless %$hData;
            return unless $hData;

            next if $hCrossIds{$hData->{_id}};
            $hCrossIds{$hData->{_id}}= 1;

            return unless $db->insert($sCrossTable, {play_id => $iPlayId, $sCrossId => $hData->{_id}});
        }
        return 1;
    });
}

sub _updateStations {
    my $self= shift;
    my $iPlayId= shift;
    my $aStations= shift;

    return $self->_updateManyToMany('play_station', 'station_id', 'stations', 'station', $iPlayId, $aStations);
}

sub _updateGenres {
    my $self= shift;
    my $iPlayId= shift;
    my $aGenres= shift;

    return $self->_updateManyToMany('play_genre', 'genre_id', 'genres', 'genre', $iPlayId, $aGenres);
}

sub _updateArrangers {
    my $self= shift;
    my $iPlayId= shift;
    my $aArrangers= shift;

    return $self->_updateManyToMany('play_arranger', 'arranger_id', 'names', 'name', $iPlayId, $aArrangers);
}

sub _updateDirectors {
    my $self= shift;
    my $iPlayId= shift;
    my $aDirectors= shift;

    return $self->_updateManyToMany('play_director', 'director_id', 'names', 'name', $iPlayId, $aDirectors);
}

sub _updateRoles {
    my $self= shift;
    my $iPlayId= shift;
    my $hRoles= shift || {};

    return $self->_db_transaction ('hoerdat', sub {
        my $db= shift;
        my $hOldRoles= $self->_getPlayRoles($iPlayId) || {};

        for my $sRole (keys %$hRoles) {
            next if $sRole eq '';
            my $sOldArtist= $hOldRoles->{$sRole};
            if ($sOldArtist) {
                delete $hOldRoles->{$sRole};

                # next if role is the same
                next if $sOldArtist eq $hRoles->{$sRole};

                # delete old role entry
                return unless $db->delete('roles', {play_id => $iPlayId, role => $sRole});
            }
            my $hArtist= $db->selectOne({names => '*'}, {name => $hRoles->{$sRole}});
            $hArtist= $db->insert('names', {name => $hRoles->{$sRole}}) unless %$hArtist;
            return unless $hArtist;
            return unless $db->insert('roles', {play_id => $iPlayId, artist_id => $hArtist->{_id}, role => $sRole});
        }

        my %oldMisc= map {$_ => 1} @{$hOldRoles->{''} || []};
        my $aMisc= $hRoles->{''} || [];
        for my $sArtist (@$aMisc) {
            if ($oldMisc{$sArtist}) {
                # is misc artist already
                delete $oldMisc{$sArtist};
                next;
            }
            my $hArtist= $db->selectOne({names => '*'}, {name => $sArtist});
            $hArtist= $db->insert('names', {name => $sArtist}) unless %$hArtist;
            return unless $hArtist;

            return unless $db->insert('roles', {play_id => $iPlayId, artist_id => $hArtist->{_id}, role => undef});
        }

        for my $sArtist (keys %oldMisc) {
            my $hArtist= $db->selectOne({names => '*'}, {name => $sArtist});
            return unless $db->delete('roles', {play_id => $iPlayId, artist_id => $hArtist->{_id}, role => undef})
        }
        delete $hOldRoles->{''};
        for my $sRole (keys %$hOldRoles) {
            my $hArtist= $db->selectOne({names => '*'}, {name => $hOldRoles->{$sRole}});
            return unless $db->delete('roles', {play_id => $iPlayId, artist_id => $hArtist->{_id}, role => $sRole})
        }
        return 1;
    });
}

sub getAllDirectories {
    my $self= shift;
    my $sth= $self->{db}{md5}->sth('SELECT DISTINCT path FROM files WHERE name LIKE ?');
    $sth->execute('%.mp_');
    return [map {$_->[0]} @{$sth->fetchall_arrayref([0])}];
}

sub getFilesByDirectory {
    my $self= shift;
    my $sDir= shift;

    our $sqBaseDir= quotemeta $self->{basedir};
    $sDir= "$sDir/" unless $sDir=~/\/$/;
    $sDir=~ s/^$sqBaseDir//;
    $sDir= "/$sDir" unless $sDir=~/^\//;
    my $sth= $self->{db}{md5}->sth('SELECT DISTINCT md5 FROM files WHERE path=?');
    $sth->execute($sDir);
    return [ sort map {$_->[0]} @{$sth->fetchall_arrayref([0])} ];
}

sub getAllPlayIds {
    my $self= shift;
    my $hPlayIds= $self->{db}{hoerdat}->selectAll({plays => '_id'}, {}, '_id');
    return [ sort {$a <=> $b} keys %$hPlayIds ];
}

sub fixFileLength {
    my $self= shift;
    my $hResult= {};

    my $sth_empty= $self->{db}{hoerdat}->sth('SELECT DISTINCT md5 FROM files WHERE length is null');
    $sth_empty->execute();
    my $sth= $self->{db}{md5}->sth('SELECT md5, name, path FROM files WHERE md5 = ?');
    while (my $sMd5= ($sth_empty->fetchrow_array())[0]) {
        $sth->execute($sMd5);
        while (my $hFile= $sth->fetchrow_hashref()) {
            my $iLength= $self->_mp3Length([ $hResult->{$sMd5}{path}, $hResult->{$sMd5}{name} ]);
            if ($iLength) {
                $hResult->{$sMd5}= $iLength;
                last;
            }
        }
        $sth->finish();
    }
    $sth_empty->finish();
    my $count= scalar keys %$hResult;
    return $self->_db_transaction ('hoerdat', sub {
        my $db= shift;
        for my $sMd5 (keys %$hResult) {
            return unless $db->update('files', { length => $hResult->{$sMd5} }, { md5 => $sMd5 });
            print "($count) $sMd5: $hResult->{$sMd5}\n";
            $count--;
        }
        return 1;
    });
}

sub getAllFilesWOPlay {
    my $self= shift;
    my $sth_md5= $self->{db}{md5}->sth('SELECT md5 FROM files');
    $sth_md5->execute();
    my $sth_plays= $self->{db}{hoerdat}->sth('SELECT COUNT(*) FROM files WHERE md5 = ?');
    my $aMd5= [];
    while (my $sMd5= ($sth_md5->fetchrow_array())[0]) {
        $sth_plays->execute($sMd5);
        push @$aMd5, $sMd5 unless ($sth_plays->fetchrow_array())[0];
        $sth_plays->finish();
    }
    $sth_md5->finish();
    return $aMd5;
}

sub getAllPlayIdsIterator {
    my $self= shift;

    return $self->{db}{hoerdat}->selectIterator({plays => '_id'});
}

sub _splitPlaylistType {
    my $self= shift;
    my $sId= shift;
    return split /\:/, $sId, 2;
}

sub getRealPlaylists {
    my $self= shift;

    my $hPlaylists= $self->{db}{hoerdat}->selectAll({playlists => '*'});
    return [ 
        sort {
            lc $a->{name} cmp lc $b->{name}
        } map {
            {
                type        => 'playlist',
                playlist_id => 'real:' . $_->{_id},
                name        => $_->{name},
            }
        } values %$hPlaylists
    ];
}

sub getVirtualPlaylists {
    my $self= shift;

    return [
        sort {
            lc $a->{playlist_id} cmp lc $b->{playlist_id}
        } map {
            my $sDir= $_;
            my $sName= $sDir;
            my $sDescr= $sDir;
            $sName=~ s/.*\/([^\/]+)\/?$/$1/;
            $sDescr=~ s/\/([^\/]+)\/?$//;
            $sDescr=~ s/^\///;
            {
                type        => 'playlist',
                playlist_id => 'virtual:' . $sDir,
                name        => $sName,
                description => $sDescr,
            }
        } @{$self->getAllDirectories()}
    ];
}

sub createPlaylist {
    my $self= shift;
    my $sName= shift;

    my $hPlaylist= $self->{db}{hoerdat}->selectOne({playlists => '*'}, {name => $sName});
    return {error => "Playlist '$sName' already exists"} if %$hPlaylist;
    $hPlaylist= $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        $db->insert('playlists', {name => $sName});
    });
    if (%$hPlaylist) {
        return {
            'ok' => 1,
            'playlist' => {
                type        => 'playlist',
                playlist_id => 'real:' . $hPlaylist->{_id},
                name        => $hPlaylist->{name},
            }
        } if %$hPlaylist;
    }
    return {error => 'Unknown error'};
}

sub renamePlaylist {
    my $self= shift;
    my ($sType, $iPlaylistId)= $self->_splitPlaylistType(shift);
    my $sNewName= shift;

    return {error => 'Playlist has to be of type "real"'} unless $sType eq 'real';

    my $hPlaylist= $self->{db}{hoerdat}->selectOne({playlists => '*'}, {_id => $iPlaylistId});
    return {error => "Playlist with ID '$iPlaylistId' does not exist"} unless %$hPlaylist;
    $hPlaylist= $self->{db}{hoerdat}->selectOne({playlists => '*'}, {name => $sNewName});
    return {error => "Playlist '$sNewName' already exists"} if %$hPlaylist;
    $hPlaylist= $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        $db->update('playlists', {name => $sNewName}, {_id => $iPlaylistId});
    });
    if (%$hPlaylist) {
        return {
            'ok' => 1,
            'playlist' => {
                type        => 'playlist',
                playlist_id => 'real:' . $hPlaylist->{_id},
                name        => $hPlaylist->{name},
            }
        } if %$hPlaylist;
    }
    return {error => 'Unknown error'};
}

sub savePlaylistOrder {
    my $self= shift;
    my ($sType, $iPlaylistId)= $self->_splitPlaylistType(shift);
    my $hOrder= shift;

    # silently drop un-real playlists
    return {} unless $sType eq 'real';
#    return {error => 'Playlist has to be of type "real"'} unless $sType eq 'real';

    my $hPlaylist= $self->{db}{hoerdat}->selectOne({playlists => '*'}, {_id => $iPlaylistId});
    return {error => "Playlist with ID '$iPlaylistId' does not exist"} unless %$hPlaylist;

    my $iPos= 0;

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        for my $iPlayId (keys %$hOrder) {
            return unless $db->update('playlist_play',
                {
                    'sort_pos'   => $hOrder->{$iPlayId}{sort_pos},
                    'random_pos' => $hOrder->{$iPlayId}{random_pos},
                },
                {
                    'playlist_id' => $iPlaylistId,
                    'play_id' => $iPlayId,
                },
            );
        }
        return {ok => 1};
    }) || return {error => "Error updating playlist"};
}

sub deletePlaylist {
    my $self= shift;
    my ($sType, $iPlaylistId)= $self->_splitPlaylistType(shift);

    return {error => 'Playlist has to be of type "real"'} unless $sType eq 'real';

    return {ok => 1} if $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        $db->delete('playlists', {_id => $iPlaylistId}) && $db->delete('playlist_play', {playlist_id => $iPlaylistId});
    });
    return {error => 'Unknown error'};
}

sub getPlaylist {
    my $self= shift;
    my ($sType, $sPlaylistId)= $self->_splitPlaylistType(shift);

    return $self->_getRealPlaylist($sPlaylistId)    if $sType eq 'real';
    return $self->_getVirtualPlaylist($sPlaylistId) if $sType eq 'virtual';
    return $self->_getSearchPlaylist($sPlaylistId) if $sType eq 'search';
    return {error => "Unknown playlist type '$sType'"};
}

sub _getRealPlaylist {
    my $self= shift;
    my $iPlaylistId= shift;

    my $hPlayIds= $self->{db}{hoerdat}->selectAll({playlist_play => '*'}, {playlist_id => $iPlaylistId}, 'play_id');
    my @plays= ();
    for my $iPlayId (keys %$hPlayIds) {
        my $hPlayData= $self->getPlayDetails($iPlayId, 'simple');
        $hPlayData->{sort_pos}=   $hPlayIds->{$iPlayId}{sort_pos};
        $hPlayData->{random_pos}= $hPlayIds->{$iPlayId}{random_pos};
        push @plays, $hPlayData;
    }
    return {items => [ @plays ]};
}

sub _getVirtualPlaylist {
    my $self= shift;
    my $sDir= shift;

    my @sFiles= @{$self->getFilesByDirectory($sDir)};

    my $hPlays= {};
    my $aAnonymousFiles= [];

    for my $sMd5 (@sFiles) {
        my $hFileData= $self->getFileDetails($sMd5, 1);
        next unless $hFileData->{name}=~ /\.(mp.)|(m4.)|(wm.)$/i;
        my $iPlayId= $hFileData->{play_id};
        if ($iPlayId) {
            $hPlays->{$iPlayId}= $self->getPlayDetails($iPlayId, 'simple') unless $hPlays->{$iPlayId};
            next;
        }
        push @$aAnonymousFiles, $hFileData;
    }

    return {items => 
        [
            $self->NumSort(sub { ($_[0]->{titles} || [''])->[0] }, values %$hPlays),
            $self->NumSort(sub { $_[0]->{name} },                  @$aAnonymousFiles),
        ]
    };
}

sub _getSearchPlaylist {
    my $self= shift;
    my $sSearch= shift;

    return {items => [ $self->{fn_fulltext}->()->query($sSearch, 30) ]};
}

sub addToPlaylist {
    my $self= shift;
    my ($sTypePlaylistId)= shift;
    my ($sType, $iPlaylistId)= $self->_splitPlaylistType($sTypePlaylistId);
    my $aPlayIds= shift;

    return {error => 'Playlist has to be of type "real"'} unless $sType eq 'real';

    my $hPlaylist= $self->{db}{hoerdat}->selectOne({playlists => '*'}, {_id => $iPlaylistId});
    return {error => "Playlist with ID '$iPlaylistId' does not exist"} unless keys %$hPlaylist;

    $self->removeFromPlaylist($sTypePlaylistId, $aPlayIds);

    my $hMaxPos= $self->{db}{hoerdat}->getHash(
        'SELECT MAX(sort_pos) as max_pos FROM playlist_play WHERE playlist_id=?',
        $iPlaylistId,
    );
    my $iPos= $hMaxPos->{max_pos} || 0;

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        for my $iPlayId (@$aPlayIds) {
            next unless %{$db->selectOne({plays => '*'}, {_id => $iPlayId})};
            return unless $db->insert('playlist_play', {
                'playlist_id' => $iPlaylistId,
                'play_id' => $iPlayId,
                'sort_pos' => ++$iPos,
            });
        }
        return {ok => 1};
    }) || {error => "Failed adding plays to playlist"};
}

sub removeFromPlaylist {
    my $self= shift;
    my ($sType, $iPlaylistId)= $self->_splitPlaylistType(shift);
    my $aPlayIds= shift;

    return {error => 'Playlist has to be of type "real"'} unless $sType eq 'real';

    my $hPlaylist= $self->{db}{hoerdat}->selectOne({playlists => '*'}, {_id => $iPlaylistId});
    return {error => "Playlist with ID '$iPlaylistId' does not exist"} unless keys %$hPlaylist;

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        for my $iPlayId (@$aPlayIds) {
            return unless $db->delete('playlist_play', {
                'playlist_id' => $iPlaylistId,
                'play_id' => $iPlayId,
            });
        }
        return {ok => 1};
    }) || return {error => "Error removing plays from playlist"};
}

sub _getFilesByPlayId {
    my $self= shift;
    my $iPlayId= shift;

    my $hFiles= $self->{db}{hoerdat}->selectAll({files => '*'}, {play_id => $iPlayId}, 'md5');
    
    for my $sMd5 (keys %$hFiles) {
        $self->_mergeFileName($hFiles->{$sMd5});
    }

    return [ sort { ($a->{play_position} || -1) <=> ($b->{play_position} || -1) } map { $_->{type}= 'file'; $_; } values %$hFiles ];
}

sub createFile {
    my $self= shift;
    my $sMd5= shift;
    my $iPlayId= shift;

    my $hFileData= $self->_getFileDataByMd5($sMd5);

    $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        $db->insert('files', {
            md5 => $sMd5,
            play_id=> $iPlayId,
            length => $self->_mp3LengthByMd5($sMd5),
        });
    }) unless scalar %$hFileData;
    return $hFileData;
}

sub createPlay {
    my $self= shift;
    my $hPlayData= shift || {};

    return $hPlayData if $hPlayData->{_id};

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        my $hPlay= $db->insert('plays', {
            audio => $hPlayData->{audio},
            description => $hPlayData->{description},
            hoerdat_id => $hPlayData->{hoerdat_id},
            rating => $hPlayData->{rating},
            title_id => -1,
            year => $hPlayData->{year},
        });
        return unless $hPlay;

        my $iPlayId= $hPlay->{_id};
        my @sTitles= map { s/\s+/ /g; $_; } @{$hPlayData->{titles} || []};
        my $sMainTitle= shift @sTitles;
        my $hTitle= $db->insert('titles', {
            play_id => $iPlayId,
            title => $sMainTitle,
        });
        return unless $hTitle;

        return unless $db->update('plays', {title_id => $hTitle->{_id}}, {_id => $iPlayId});

        for my $sTitle (@sTitles) {
            return unless $db->insert('titles', {
                play_id => $iPlayId,
                title => $sTitle,
            });
        }
        return $hPlay;
    });
}

sub createFilePlay {
    my $self= shift;
    my $sMd5= shift;

    my $hFile= $self->{db}{hoerdat}->selectOne({files => '*'}, {md5 => $sMd5});
    my $hPlay= {};
    $hPlay= $self->{db}{hoerdat}->selectOne({plays => '*' }, $hFile->{play_id});

    return $hPlay if %{$hPlay};

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        $hPlay= $self->createPlay();
        return unless $hPlay;

        if (%{$hFile}) {
            return unless $db->update('files', {play_id => $hPlay->{_id}}, $hFile->{_id});

            return $hPlay;
        }

        return unless $db->insert('files', {
            md5 => $sMd5,
            play_id => $hPlay->{_id},
            length => $self->_mp3LengthByMd5($sMd5),
        });

        return $hPlay;
    });
}

sub setRating {
    my $self= shift;
    my $iPlayId= shift;
    my $iRating= shift || undef;

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        $db->update('plays', {rating => $iRating}, $iPlayId);
        $self->getPlayDetails($iPlayId);
    });
}

sub getFileData {
    my $self= shift;
    return $self->getFileDetails(shift, 1);
}

sub playFile {
    my $self= shift;
    my $sMd5= shift;

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        $db->update('files', {last_played => time}, {md5 => $sMd5});
    });
}

sub getPlayDetails {
    my $self= shift;
    my $iPlayId= shift;
    my $bSimple= shift;

    my $hPlayData= $self->_getPlayData($iPlayId);
    my $aTitles= $self->_getPlayTitles($iPlayId, $hPlayData->{title_id});
    my $aFileData= $self->_getFilesByPlayId($iPlayId);
    map { $_->{'.guessed'}= $self->_parseFileName($_->{name}) } @$aFileData;

    my $hResult= {
        type => 'play',
        play_id => $iPlayId,
        titles => $aTitles,
        rating => $hPlayData->{rating} || 0,
        hoerdat_id => $hPlayData->{hoerdat_id},
        authors => $self->_getPlayAuthors($iPlayId),
        directors => $self->_getPlayNames('director', $iPlayId),
        genres => $self->_getPlayGenres($iPlayId),
        stations => $self->_getPlayStations($iPlayId),
        files => $aFileData,
    };
    if ($bSimple) {
        $hResult->{'.minimized'}= 1;
    }
    else {
        my $hDetails= {
            description => $hPlayData->{description},
            arrangers => $self->_getPlayNames('arranger', $iPlayId),
            keywords => $self->_getPlayKeywords($iPlayId),
            roles => $self->_getPlayRoles($iPlayId),
            year => $hPlayData->{year},
        };
        @$hResult{keys %$hDetails}= values %$hDetails;
    }
    return $hResult;
}

sub getFileDetails {
    my $self= shift;
    my $sMd5= shift;

    my $hFileData= $self->_getFileDataByMd5($sMd5);
    $hFileData->{type}= 'file';
    $hFileData->{'.guessed'}= $self->_parseFileName($hFileData->{name});
    return $hFileData;
}

sub setFileDetails {
    my $self= shift;
    my $sMd5= shift;
    my $hData= shift;

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        my $hFileData= $self->_getFileDataByMd5($sMd5);
        my $hPlayData= $self->setPlayDetails(undef, $hData);
        return unless $hPlayData;

        for my $sField ('play_id', 'addition', 'part_num', 'part_count', 'last_played') {
            $hFileData->{$sField}= $hData->{$sField} if exists $hData->{$sField};
        }
        $hFileData->{length}= $self->_mp3Length([ $hFileData->{dir}, $hFileData->{name}, ]);

        my $iPlayId= $hPlayData->{play_id};

        return unless $db->delete('files', {md5 => $sMd5});
        return unless $db->insert('files', {
            md5 => $sMd5,
            addition => $hFileData->{addition},
            part_num => $hFileData->{part_num},
            part_count => $hFileData->{part_count},
            play_id => $iPlayId,
            length => $hFileData->{length},
        });
        return $self->getPlayDetails($iPlayId);
    });
}

sub setPlayDetails {
    my $self= shift;
    my $iPlayId= shift;
    my $hData= shift;

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        my $iOldPlayId= $iPlayId || 0;
        my $hPlayData= $self->_getPlayData($iPlayId);
        my $iOldPlayRating= $hPlayData->{rating};
        my $sOldHoerdatId= $hPlayData->{hoerdat_id} || '';
        my $sHoerdatId= $hData->{hoerdat_id} || '';
        unless ($sOldHoerdatId eq $sHoerdatId) {
            if (!$sOldHoerdatId && $iPlayId) {
                # this was an empty plays-record - delete it
                return unless $db->delete('titles',         {play_id => $iPlayId});
                return unless $db->delete('playlist_play',  {play_id => $iPlayId});
                return unless $db->delete('plays',          {_id     => $iPlayId});
            }
            # try to fetch play with current hoerdat_id
            $hPlayData= $self->_getPlayData({hoerdat_id => $hData->{hoerdat_id}});
            return unless $hPlayData;

            $iPlayId= $hPlayData->{_id};
        }
        if ($iPlayId) {
            my $iMainTitleId= $self->_updateTitles($iPlayId, $hData->{titles});
            my $hUpdate= {
                'title_id' => $iMainTitleId,
                'audio' => $hData->{audio},
                'description' => $hData->{description},
                'year' => $hData->{year},
            };
            # copy old rating's value
            $hUpdate->{rating}= $iOldPlayRating if $iOldPlayRating && !$hPlayData->{rating};
            return unless $db->update('plays', $hUpdate, $iPlayId) ;
        }
        else {
            # or create new play entry
            $hData->{rating}= $iOldPlayRating if $iOldPlayRating;
            $hPlayData= $self->createPlay($hData);
            return unless $hPlayData;

            $iPlayId= $hPlayData->{_id};
        }
        if ($iOldPlayId != $iPlayId) {
            return unless $db->update('files', { play_id => $iPlayId }, { play_id => $iOldPlayId });
        }

        return unless $self->_updateAuthors($iPlayId, $hData->{authors});
        return unless $self->_updateArrangers($iPlayId, $hData->{arrangers});
        return unless $self->_updateDirectors($iPlayId, $hData->{directors});
        return unless $self->_updateStations($iPlayId, $hData->{stations});
        return unless $self->_updateGenres($iPlayId, $hData->{genres});
        return unless $self->_updateRoles($iPlayId, $hData->{roles});

        return unless $self->_getPlayTitles($iPlayId, $hPlayData->{title_id});

        my $hPlayDetails= $self->getPlayDetails($iPlayId);
#        $self->{fn_fulltext}->()->associate('play', $iPlayId, $hPlayDetails);
        return $hPlayDetails;
    });
}

sub setExtendedFileDetails {
    my $self= shift;
    my $sMd5= shift;
    my $hData= shift;

    my $hFileData= $self->_getFileDataByMd5($sMd5);
    $hFileData->{addition}=   $hData->{addition}   || undef;
    $hFileData->{part_num}=   $hData->{part_num}   || undef;
    $hFileData->{part_count}= $hData->{part_count} || undef;

    my $iOldPlayId;

    my $hItemDetails= $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        if ($hFileData->{play_id}) {
            if ($hData->{remove_play_id}) {
                $iOldPlayId= $hFileData->{play_id};
                $hFileData->{play_id}= undef;
                return unless $db->delete('files', {md5 => $sMd5});
                return unless $self->__cleanupDB();
            }
        }

        my $hUpdate= {};
        for my $sField ('play_id', 'addition', 'part_num', 'part_count', 'last_played') {
            $hUpdate->{$sField}= $hFileData->{$sField} if exists $hFileData->{$sField};
        }

        unless ($hFileData->{play_id}) {
            if ($hData->{new_play_id}) {
                $hUpdate->{play_id}= $hData->{new_play_id};
                $hUpdate->{md5}= $sMd5;
                $hUpdate->{length} = $self->_mp3LengthByMd5($sMd5);
                return unless $db->insert('files', $hUpdate);
                return $self->getPlayDetails($hUpdate->{play_id});
            }
            if ($hData->{title}) {
                $hFileData->{titles}= [$hData->{title}];
                return $self->setFileDetails($sMd5, $hFileData);
            }
        }

        return unless $db->update('files', $hUpdate, {md5 => $sMd5});
        return $hFileData->{play_id} ? $self->getPlayDetails($hFileData->{play_id}) : $self->getFileDetails($sMd5);
    });

    return {error => "Error updateing file's extended data"} unless $hItemDetails;

    my $result= [];
    push @$result, $self->getPlayDetails($iOldPlayId) if $iOldPlayId && (! $hItemDetails->{play_id} || $hItemDetails->{play_id} != $iOldPlayId);
    push @$result, $hItemDetails;
    return {items => $result};
}

sub setPlaysFileOrder {
    my $self= shift;
    my $iPlayId= shift;
    my $hOrder= shift;

    return $self->_db_transaction('hoerdat', sub {
        my $db= shift;
        for my $sMd5 (keys %$hOrder) {
            return unless $db->update('files', {play_order => $hOrder->{$sMd5}}, {play_id => $iPlayId, md5 => $sMd5});
        }
        return $self->getPlayDetails($iPlayId);
    });
}

1;

