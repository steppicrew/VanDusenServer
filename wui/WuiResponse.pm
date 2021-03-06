package WuiResponse;

use strict;
use warnings;

use CGI;
use CGI::Cookie;
use Encode;
use JSON::XS;
use File::Spec;
use Cwd;

use Data::Dumper;

use FileDB;
use FileEncode;
use ParseHoerdat;
use Conf;

my $conf= Conf->new(
    './wui.conf',
    {
        basedir    => sub { my $v= Cwd::abs_path(shift); $v=~ s/\/$//; $v },
        fileurl    => undef,
        encodeurl  => undef,
        md5db      => undef,
        hoerdatdb  => undef,
        fulltextdb => undef,
        timeout    => undef,
        readonly   => undef,
        timeout    => 31_536_000,
        users      => undef,
        pingsemaphore => undef,

        encode_tempdir => sub { my $v= Cwd::abs_path(shift || 'tmp'); $v=~ s/\/$//; $v },
        encode_tempcount => 100,
    }
);

my $filedb= FileDB->new($conf);

my @sPlayerStatus= ('repeat', 'shuffle', 'stop-after', 'playlist-id', 'item-uid', 'time-mode');

my %aSessions= ();
my $iSessionTimeout= 5 * 3_600;

sub new {
    my $class= shift;
    my %httpData= @_;

    my $hCookies= CGI::Cookie->parse($httpData{cookies});

    my $self= {
        path => $httpData{path},
        cmd => $httpData{params}{cmd},
        callback => $httpData{params}{callback},
        # cookies starting with "a_" are interpreted as arrays
        cookies => { map {
            if (/^a_/) {
                $_ => [ $hCookies->{$_}->value() ];
            }
            else {
                $_ => scalar $hCookies->{$_}->value();
            }
        } keys %{$hCookies} },
#        session => undef,
        cgi => CGI->new(),
        debug => $httpData{debug},
        readonly => $conf->get('users') ? 1 : 0,
        mobile => $httpData{mobile},
    };

    bless $self, $class;
    $self->{data}= $self->_encode(decode_json($httpData{params}{data})) if $httpData{params}{data};

    $self->{cmds}= {
        'login'                 => sub { $self->_cmd_login() },
        'index'                 => sub { $self->_cmd_getIndex() },
        'ping'                  => sub { $self->_cmd_ping() },
        'add-to-playlist'       => sub { $self->_cmd_addToPlaylist() },
        'create-playlist'       => sub { $self->_cmd_createPlaylist() },
        'delete-playlist'       => sub { $self->_cmd_deletePlaylist() },
        'getdetails'            => sub { $self->_cmd_getDetails() },
        'getfiledata'           => sub { $self->_cmd_getFileData() },
        'getglobaldata'         => sub { $self->_cmd_getGlobalData() },
        'getplaylist'           => sub { $self->_cmd_getPlaylist() },
        'getplaylists'          => sub { $self->_cmd_getPlaylists() },
        'player-status'         => sub { $self->_cmd_setPlayerStatus() },
        'prepareFile'           => sub { $self->_cmd_prepareFile() },
        'queryhoerdat'          => sub { $self->_cmd_queryHoerdat() },
        'remove-from-playlist'  => sub { $self->_cmd_removeFromPlaylist() },
        'rename-playlist'       => sub { $self->_cmd_renamePlaylist() },
        'save-playlist-order'   => sub { $self->_cmd_savePlaylistOrder() },
        'search'                => sub { $self->_cmd_search() },
        'set-file-lastplayed'   => sub { $self->_cmd_setFileLastPlayed() },
        'set-lastplaylist'      => sub { $self->_cmd_setLastPlaylist() },
        'setdetails'            => sub { $self->_cmd_setDetails() },
        'setextendedfiledetails' => sub { $self->_cmd_setExtendedFileDetails() },
        'setplaysfileorder'     => sub { $self->_cmd_setPlaysFileOrder() },
        'setrating'             => sub { $self->_cmd_setRating() },
    };

    bless $self, $class;
}

sub _getSession {
    my $self= shift;

    %aSessions= map { $_ => $aSessions{$_} } grep { $aSessions{$_}{valid_until} > time } keys %aSessions;

    my $sid= $self->{cookies}{sid} || '';
    unless ($sid) {
        $sid= substr($sid . (int rand 10000), 0, 12) while length $sid < 12;
        $self->{cookies}{sid}= $sid;
    }
    my $hSession= $aSessions{$sid} || {};
    $hSession->{sid}= $sid;
    $hSession->{valid_until}= time + $iSessionTimeout;

    $aSessions{$sid}= $hSession;
    return $hSession;
}

sub build {
    my $self= shift;

    # don't trust cookies if we have session data (there could be multiple requests be running at a time)
    my $hSession= $self->_getSession();
    for (keys %{$hSession->{cookies}}) {
        $self->{cookies}{$_}= $hSession->{cookies}{$_};
    }
    $hSession->{cookies}= $self->{cookies};

    my $cmd= $self->{cmd} || 'index';

    if ($conf->get('users') && ! $hSession->{login}) {
        return $self->_buildPage({
            title => "VanDusen Player - Login",
            body => _loginBody(),
        }) unless $cmd eq 'login' || $cmd eq 'ping';
    }

    if ($hSession->{login} && $hSession->{login}{admin}) {
        $self->{readonly}= 0;
    }

    my $sub= $self->{cmds}{ $cmd };
    return $sub ? $sub->() : ();
}

sub _getCookies {
    my $self= shift;
    return [
        map {
            $self->{cgi}->cookie(
                -name => $_,
                -value => $self->{cookies}{$_},
                -expires => '+' . $conf->get('timeout') . 's',
            )
        } keys %{$self->{cookies}}
    ];
}

sub _buildJson {
    my $self= shift;
    my $data= shift || {'error' => 'unknown error'};

    $data= encode_json($self->_decode($data));
    # if JSONP request, call callback
    $data= $self->{callback} . '(' . $data . ');' if $self->{callback};

    return {
        'Content-Type' => 'text/javascript; charset=utf-8',
        'Set-Cookie' => $self->_getCookies(),
    }, $data;
}

sub _buildErrorPage {
    my $self= shift;
    my $error= shift;

    return $self->_buildPage({
        title => 'An Error Occured!',
        body => $error,
    });
}

sub _buildPage {
    my $self= shift;
    my $pageData= shift;

    my @scripts= (
        { type => 'application/javascript', src => '/static/jquery.js'},
        { type => 'application/javascript', src => '/static/jquery-ui.js'},
        { type => 'application/javascript', src => '/static/jquery.marquee.js'},
        { type => 'application/javascript', src => '/static/jquery.jplayer.js'},
    );
    push @scripts, { type => 'application/javascript', src => '/static/jquery.mobile.js'} if $self->{mobile};
    push @scripts, { type => 'application/javascript', code => '
        (function() {
            if (typeof console === "undefined") console= {}
            var c= ["debug", "log", "warn", "error"]
            for (var i in c) {
                if (!console[c[i]]) {
                    console[c[i]]=function() {}
                }
            }
            if (typeof VD === "undefined") VD= {};
            VD.mobile= ' . ($self->{mobile} ? 'true' : 'false') . ';
        })()
    ' };
    push @scripts, { type => 'application/javascript', code => $pageData->{script} } if $pageData->{script};
    for my $script (glob("static/vd.*.js"), 'static/wui.js') {
        push @scripts, { type => 'application/javascript', src => '/' . $script };
    }

    my @css= (
        { src => '/static/css/all.css' },
        { src => '/static/css/jquery-ui.css' },
    );
    push @css, { src => '/static/css/jquery.mobile.css' }, { src => '/static/css/mobile.css' } if $self->{mobile};

    return
        {
            'Content-Type' => 'text/html; charset=utf-8',
            'Set-Cookie' => $self->_getCookies(),
        },
        join "",
            $self->{cgi}->start_html(
                {
                    -title => $pageData->{title} || 'unknown',
                    -style => [ @css ],
                    -encoding => 'utf-8',
                    -script => [ @scripts ],
                    -lang => 'de-DE',
                    -head=>[
                        $self->{cgi}->Link({
                            -rel=>'shortcut icon',
                            -href=>'/static/favicon.ico'
                        }),
                    ],
                }
            ),
            $pageData->{body} || $self->_indexBody(),
            $self->{cgi}->end_html();
}

sub _decode {
    my $self= shift;
    my $param= shift;
    unless (ref $param) {
        # try to decode first as utf8, then as unicode and finally return string unchanged
        # disable warnings and croaks
        my $result;
        local $SIG{__WARN__} = sub {};
        local $SIG{__DIE__} = sub {};
        for my $encoding ('utf8', 'unicode') {
            eval {
                $result= decode($encoding, $param);
            };
            return $result unless $@;
        }
        return $param;
    }
    return [ map { $self->_decode($_) } @$param ] if ref $param eq 'ARRAY';
    return { map { my $key= $_; $self->_decode($key) => $self->_decode($param->{$key}) } keys %$param } if ref $param eq 'HASH';
    die "Don't know what to decode: '$param'";
}

sub _encode {
    my $self= shift;
    my $param= shift;
    return encode('utf8', $param) unless ref $param;
    return [ map { $self->_encode($_) } @$param ] if ref $param eq 'ARRAY';
    return { map { my $key= $_; $self->_encode($key) => $self->_encode($param->{$key}) } keys %$param } if ref $param eq 'HASH';
    die "Don't know what to encode: '$param'";
}

sub _errorReadOnly {
    my $self= shift;
    my $data= shift || {error => 'Read only mode'};

    return $self->_buildJson($data);
}

sub _cmd_getIndex {
    my $self= shift;

    return $self->_buildPage({
        title => "VanDusen Player",
        body => _indexBody(),
    });
}

sub _cmd_login {
    my $self= shift;

    my %users= ();
    map {
        my ($user, $admin, $password)= map {s/\\(.)/$1/g; $_} split /\:\:/;
        return unless defined $user && defined $admin && defined $password;
        $users{$user} = {
            user => $user,
            admin => $admin,
            password => $password,
        }
    } split /\|\|/, $conf->get('users');

    my $login= 0;

    if (defined $self->{data}{user}) {
        my $user= $users{$self->{data}{user}};
        if ($user && $user->{password} eq $self->{data}{password}) {
            my $hSession= $self->_getSession();
            $hSession->{login}= $user;
            $login= 1
        }
    }
    return $self->_buildJson({
        'success' => $login,
    });
}

sub _cmd_ping {
    my $self= shift;

    my $result= "ok";
    if ($conf->get('pingsemaphore')) {
        my $fh;
        if (open($fh, ">", $conf->get('pingsemaphore'))) {
            print $fh "ping";
            close $fh;
        }
        else {
            $result= "failed";
        }
    }

    return $self->_buildJson({
        'ping' => 'ok',
    });
}

sub _cmd_getGlobalData {
    my $self= shift;

    my $hPlayerStatus= {};
    for my $sStatus (@sPlayerStatus) {
        $hPlayerStatus->{$sStatus}= $self->{cookies}{'playerstatus_' . $sStatus};
    }
    return $self->_buildJson({
        'fileurl'          => $conf->get('fileurl'),
        'encodeurl'        => $conf->get('encodeurl'),
        'player-status'    => $hPlayerStatus,
        'last-playlist-id' => $self->{cookies}{last_playlist_id},
    });
}

sub _cmd_setFileLastPlayed {
    my $self= shift;

    return $self->_errorReadOnly() if $self->{readonly};

    my $sMd5= $self->{data}{md5};
    $filedb->playFile($sMd5);
    return $self->_buildJson({});
}

sub _cmd_setLastPlaylist {
    my $self= shift;

    $self->{cookies}{last_playlist_id}= $self->{data}{playlist_id};

    return $self->_buildJson({});
}

sub _cmd_setPlayerStatus {
    my $self= shift;

    my $hPlayerStatus= $self->{data}{'player-status'};
    for my $sStatus (@sPlayerStatus) {
        $self->{cookies}{'playerstatus_' . $sStatus}= $hPlayerStatus->{$sStatus};
    }
    return $self->_buildJson({});
}

sub _cmd_setRating {
    my $self= shift;

    my $iPlayId= $self->{data}{play_id};
    return $self->_errorReadOnly($filedb->getPlayDetails($iPlayId)) if $self->{readonly};

    my $iNewRating= $self->{data}{rating};

    return $self->_buildJson($filedb->setRating($iPlayId, $iNewRating));
}

sub _cmd_getFileData {
    my $self= shift;

    my $sPath= $self->{data}{dir} || '';
    my $sFileName= $self->{data}{name} || '';

    return $self->_buildJson(
        $filedb->getFileDetails(File::Spec->catdir($sPath, $sFileName), 1),
    );
}

sub _cmd_getDetails {
    my $self= shift;

    my $sType= $self->{data}{type};

    if ($sType eq 'file') {
        return $self->_buildJson(
            $filedb->getFileDetails($self->{data}{md5}),
        );
    }
    elsif ($sType eq 'play') {
        return $self->_buildJson(
            $filedb->getPlayDetails($self->{data}{play_id}),
        );
    }
    return $self->_buildJson({});
}

sub _cmd_setDetails {
    my $self= shift;

    my $sType= $self->{data}{type};

    if ($sType eq 'file') {
        return $self->_errorReadOnly($filedb->getFileDetails($self->{data}{md5})) if $self->{readonly};
        return $self->_buildJson($filedb->setFileDetails($self->{data}{md5}, $self->{data}{data}));
    }
    elsif ($sType eq 'play') {
        return $self->_errorReadOnly($filedb->getPlayDetails($self->{data}{play_id})) if $self->{readonly};
        return $self->_buildJson($filedb->setPlayDetails($self->{data}{play_id}, $self->{data}{data}));
    }
}

sub _cmd_setExtendedFileDetails {
    my $self= shift;

    return $self->_errorReadOnly() if $self->{readonly};

    my $sMd5= $self->{data}{md5};
    my $hData= $self->{data}{data};

    return $self->_buildJson($filedb->setExtendedFileDetails($sMd5, $hData));
}

sub _cmd_setPlaysFileOrder {
    my $self= shift;

    my $iPlayId= $self->{data}{play_id};
    return $self->_errorReadOnly($filedb->getPlayDetails($iPlayId)) if $self->{readonly};

    my $hOrder= $self->{data}{order};

    return $self->_buildJson($filedb->setPlaysFileOrder($iPlayId, $hOrder));
}

sub _cmd_queryHoerdat {
    my $self= shift;

    my $sTitle= $self->{data}{title} || '';
    my $sAuthorName= $self->{data}{author_name} || '';
    my $sAuthorGivenName= $self->{data}{author_given_name} || '';

    my $hoerdat= ParseHoerdat->new({
        title => $sTitle,
        author_name => $sAuthorName,
        author_given_name => $sAuthorGivenName,
    });

    return $self->_buildJson(
        $hoerdat->query()
    );
}

sub _cmd_getPlaylists {
    my $self= shift;

    return $self->_buildJson([
        @{$filedb->getRealPlaylists()},
        @{$filedb->getVirtualPlaylists()},
    ]);
}

sub _cmd_createPlaylist {
    my $self= shift;

    return $self->_errorReadOnly() if $self->{readonly};

    my $sName= $self->{data}{name};
    return $self->_buildJson($filedb->createPlaylist($sName));
}

sub _cmd_renamePlaylist {
    my $self= shift;

    return $self->_errorReadOnly() if $self->{readonly};

    my $sPlaylistId= $self->{data}{playlist_id};
    my $sNewName= $self->{data}{newname};
    return $self->_buildJson($filedb->renamePlaylist($sPlaylistId, $sNewName));
}

sub _cmd_savePlaylistOrder {
    my $self= shift;

    return $self->_errorReadOnly() if $self->{readonly};

    my $sPlaylistId= $self->{data}{playlist_id};
    my $hOrder= $self->{data}{order};
    return $self->_buildJson($filedb->savePlaylistOrder($sPlaylistId, $hOrder));
}

sub _cmd_deletePlaylist {
    my $self= shift;

    return $self->_errorReadOnly() if $self->{readonly};

    my $sPlaylistId= $self->{data}{playlist_id};
    return $self->_buildJson($filedb->deletePlaylist($sPlaylistId));
}

sub _cmd_addToPlaylist {
    my $self= shift;

    return $self->_errorReadOnly() if $self->{readonly};

    my $sPlaylistId= $self->{data}{playlist_id};
    my $aPlays= $self->{data}{plays};
    return $self->_buildJson($filedb->addToPlaylist($sPlaylistId, $aPlays));
}

sub _cmd_removeFromPlaylist {
    my $self= shift;

    return $self->_errorReadOnly() if $self->{readonly};

    my $sPlaylistId= $self->{data}{playlist_id};
    my $aPlays= $self->{data}{plays};
    return $self->_buildJson($filedb->removeFromPlaylist($sPlaylistId, $aPlays));
}

sub _cmd_getPlaylist {
    my $self= shift;

    my $sPlaylistId= $self->{data}{playlist_id};

    return $self->_buildJson($filedb->getPlaylist($sPlaylistId));
}

sub _cmd_search {
    my $self= shift;

    my $sSearch= $self->{data}{search};

    return $self->_buildJson($filedb->getPlaylist("search:$sSearch"));
}

sub _cmd_prepareFile {
    my $self= shift;

    my $sFileName= $self->{data}{file};
    my $sFormat= $self->{data}{format};

    my $encoder= FileEncode->new($conf);

    return $self->_buildJson($encoder->encode({
        filename => $sFileName,
        format => $sFormat,
    }));
}

sub _indexBody {
    return '
        <div id="body-c">
            <div id="body">
                <div class="embed">
                    <div id="jquery_jplayer"></div>
                </div>
                <div id="player" class="container" state="stopped">
                    <div class="info">
                    </div>
                    <div class="progress">
                        <div class="progressbar"></div>
                    </div>
                    <ul class="playctl ui-widget ui-helper-clearfix">
                        <li class="play play-pause ui-state-default ui-corner-all ui-state-disabled">
                            <span class="ui-icon ui-icon-play"></span>
                        </li>
                        <li class="pause play-pause ui-state-default ui-corner-all ui-state-disabled">
                            <span class="ui-icon ui-icon-pause"></span>
                        </li>
                        <li class="prev ui-state-default ui-corner-all ui-state-disabled">
                            <span class="ui-icon ui-icon-seek-first"></span>
                        </li>
                        <li class="next ui-state-default ui-corner-all ui-state-disabled">
                            <span class="ui-icon ui-icon-seek-end"></span>
                        </li>
                        <li class="repeat ui-state-default ui-corner-all">
                            <span class="ui-icon ui-icon-refresh" title="Playlist wiederholen"></span>
                        </li>
                        <li class="shuffle ui-state-default ui-corner-all">
                            <span class="ui-icon ui-icon-shuffle" title="Zufallsreihenfolge"></span>
                        </li>
                        <li class="stop-after ui-state-default ui-corner-all">
                            <span class="ui-icon ui-icon-arrowstop-1-e" title="Nach diesem Titel anhalten"></span>
                        </li>
                    </ul>
                </div>
                <div id="input" class="container">
                    <div id="pl-tabs">
                        <span class="right">&nbsp;</span>
                        <span class="tab" id="pl-player">Player</span
                        ><span class="tab" id="pl-source">Quelle</span
                        ><span class="tab" id="pl-target">Bearbeiten</span>
                    </div>
                    <div id="operation">
                        <select id="playlistselect">
                        </select>
                        <ul id="playlistop" class="ui-widget ui-helper-clearfix">
                            <li class="pl-new ui-state-default ui-corner-all">
                                <span class="ui-icon ui-icon-document" title="Neue Playlist erstellen"></span>
                            </li>
                            <li class="pl-rename ui-state-default ui-corner-all">
                                <span class="ui-icon ui-icon-pencil" title="Playlist umbenennen"></span>
                            </li>
                            <li class="pl-open ui-state-default ui-corner-all">
                                <span class="ui-icon ui-icon-folder-open" title="Playlist (erneut) laden"></span>
                            </li>
                            <li class="pl-delete ui-state-default ui-corner-all">
                                <span class="ui-icon ui-icon-trash" title="Playlist l&ouml;schen"></span>
                            </li>
                            <li class="pl-save ui-state-default ui-corner-all">
                                <span class="ui-icon ui-icon-disk" title="H&ouml;rspielreihenfolge in aktueller Playlist speichern"></span>
                            </li>
                            <li class="pl-add ui-state-default ui-corner-all">
                                <span class="ui-icon ui-icon-plus" title="ausgew&auml;hlte H&ouml;rspiele zur Playlist hinzuf&uuml;gen"></span>
                            </li>
                            <li class="pl-remove ui-state-default ui-corner-all">
                                <span class="ui-icon ui-icon-minus" title="ausgew&auml;hlte H&ouml;rspiele aus der Playlist entfernen"></span>
                            </li>
                        </ul>
                        <div id="filter">
                            <div id="ratingfilter"></div>
                        </div>
                        <div id="search_c">
                            <form id="searchform">
                                <input type="text" id="search" />
                            </form>
                        </div>
                        <div id="selection-op">
                            <div class="right">
                                <span class="sort-abc">A&rarr;Z</span>
                                <span class="sort-orig">orig</span>
                                <span class="sort-cba">Z&rarr;A</span>
                                <span class="sort-scramble">mischen</span>
                            </div>
                            Auswahl 
                            <span class="select-all">alle</span>
                            <span class="select-none">keins</span>
                            <span class="select-invert">umkehren</span>
                        </div>
                    </div>
                    <div id="main-c">
                        <div id="main">
                            <div id="list-player"></div>
                            <div id="list-target"></div>
                            <div id="list-source"></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div id="dialog-iteminfo">
            <div class="iteminfo">
            </div>
        </div>
        <div id="edit-item">
            <div id="edit-itemdetails">
            </div>
        </div>
        <div id="edit-playlist">
            <div class="pl-edit">
            </div>
        </div>
        <div id="json-busy">
            working...
        </div>
        <div id="dummyplayer" style="display: none;">
            <span class="jp-play"></span>
            <span class="jp-pause"></span>
            <span class="jp-stop"></span>
            <span class="jp-video-play"></span>
            <span class="jp-seek-bar"></span>
            <span class="jp-play-bar"></span>
            <span class="jp-mute"></span>
            <span class="jp-unmute"></span>
            <span class="jp-volume-bar"></span>
            <span class="jp-volume-bar-value"></span>
            <span class="jp-current-time"></span>
            <span class="jp-duration"></span>
        </div>
    ';
}

sub _loginBody {
    return '
        <div class="error">
        </div>
        <form id="login">
            <table>
                <tr><td>Name:</td><td><input type="text" name="user" id="user" /></td></tr>
                <tr><td>Passwort:</td><td><input type="password" name="password" id="password" /></td></tr>
                <tr><td colspan="2"><input type="submit" value="Login" /></td></tr>
            </table>
        </form>
        <script>
            jQuery(function($) {
                $("form#login").submit(function() {
                    VD.Util.doJsonRequest(
                        "login",
                        {
                            user: $("input#user").val(),
                            password:$("input#password").val(),
                        },
                        null,
                        function(data) {
                            if (parseInt(data.success)) {
                                window.location.reload();
                                return;
                            }
                            $(".error").html("Login Fehlgeschlagen!");
                        }
                    );
                    return false;
                })
            });
        </script>
    ';
}

1;
