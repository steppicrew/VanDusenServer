
// ============================================================================
//     VLC Player Library
// ============================================================================

jQuery(function($) {

    VD.Player= (function() {

// ============================================================================
//      Import Modules
// ============================================================================

    var Event= VD.Event;
    var Util= VD.Util;
    var Playlist= VD.Playlist;

// ============================================================================
//      Basic utility functions
// ============================================================================

    var _playlist= null;
    var _item_uid= null;
    var _item_file_index= -1;
    var _base_url= 'file://';

    var _play_buttons= [ 'play', 'pause', 'prev', 'next' ];

    // status information of player (shuffle, last playlist, last played position etc.)
    var _player_status= {};
    var _player_status_types= {
        'repeat': 'button',
        'shuffle': 'button',
        'stop-after': 'button',
        'playlist': 'object',
        'item-uid': 'string',
        'time-mode': 'string',
    };
    var _time_modes= [ 'position', 'length', 'remain', ];
    var _player_status_timeout= 1000;
    var _slider_max= 1000;

    var _$player= $('#jquery_jplayer');

    var _play_button_cache= {};

    // add regular play buttons (play, prev, next...)
    Util.forEach(_play_buttons, function(button) {_play_button_cache[button]= $('.playctl .' + button)})

    // add player status buttons (repeat, shuffle...)
    Util.forEach(_player_status_types, function(type, button) {
        if (type !== 'button') return // continue
        _play_button_cache[button]= $('.playctl .' + button);
    })

    var getItem= function(uid) {
        if (_playlist) return _playlist.getItem(uid);
        return null;
    };

    var queue= function(uid) {
        if (!getItem(uid)) {
            stop();
            return;
        }
        queueItem(uid);
    }

    var play= function(uid) {
        queue(uid);
        playFile();
    };

    // update player status buttons (shuffle, repeat etc)
    var updatePlayerStatusButtons= function() {
        Util.forEach(_player_status_types, function(bt_type, button) {
            if (bt_type !== 'button') return // continue
            if (_player_status[button]) {
                _play_button_cache[button].addClass('ui-state-active');
            }
            else {
                _play_button_cache[button].removeClass('ui-state-active');
            }
        })
    }

    var _updatePlayerStatus= function(fn) {
        // remove unneeded playlist from player status
        var player_status= _player_status;
        delete player_status.playlist;
        Util.doJsonRequest(
            'player-status',
            {
                'player-status': player_status,
            },
            null,
            fn
        );
        updatePlayerStatusButtons();
    };

    var updateTimeMode= function() {
        var $timeinfo= $('#player .timeinfo');
        if ($timeinfo.hasClass('time-mode-' + _player_status['time-mode'])) return;

        var found= false;
        Util.forEach(_time_modes, function(mode) {
            if (mode === _player_status['time-mode']) {
                found= true;
                $timeinfo.addClass('time-mode-' + mode);
            }
            else {
                $timeinfo.removeClass('time-mode-' + mode);
            }
        });
        if (found) return;

        $timeinfo.addClass('time-mode-' + _time_modes[0]);
        _player_status['time-mode']= _time_modes[0];
    };

    var updateFileNum= function() {
        var $file_no= $('#player .file-no');
        var item= getItem(_item_uid);
        if (!item) return Util.setHtml($file_no, '');

        var play_files= item.get('play_files');
        if (play_files.length < 2) return Util.setHtml($file_no, '');

        Util.setHtml($file_no, (_item_file_index + 1) + '/' + play_files.length);
    };

    var setup= function(status, base_url, fn_getPlaylist, fn_loadPlaylist) {
        _base_url= base_url;
        _player_status= {};
        Util.forEach(_player_status_types, function(type, status_type) {
            var value= status[status_type];
            switch (type) {
                case 'button':
                    value= parseInt(value, 10) ? true : false;
                    break

                case 'integer':
                    value= parseInt(value, 10);
                    break
            }
            _player_status[status_type]= value;
        })
        updatePlayerStatusButtons();
        updateTimeMode();

        // load player's playlist
        var playlist_id= status['playlist-id'];
        if (!playlist_id) return;

        var playlist= fn_getPlaylist(playlist_id);
        if (!playlist) return

        setPlaylist(playlist, function(items) {
            var item_uid= status['item-uid'];
            if (item_uid) {
                queueItem(item_uid);
            }
            Event.fire('changedPlayersOrder', _player_status.shuffle ? 'random' : 'orig');
        });
    };

    // sets current playlist
    var setPlaylist= function(playlist, fn_load) {
        _playlist= playlist;
        if (playlist == null) return;

        playlist.load(function(items) {
            Event.fire('changedPlayersPlaylist', playlist);
            if (fn_load) fn_load(items);
        });
    }

    var _init= function() {
        // initialize player
        $("#jquery_jplayer").jPlayer( {
            ready: function () {
                this.element.jPlayer("volumeMax")
                .jPlayer("onSoundComplete", function() {updatePlayerStatus('stopped')});
            },
//            oggSupport: true,
            swfPath: "/static/",
        });

        // manage player's buttons
        $('ul.playctl li').live('click', function() {
            if ($(this).hasClass('ui-state-disabled')) return false;
            if ($(this).hasClass('play')) {
                if (_$player.jPlayer('getData', 'diag.playedTime') > 0) { // PAUSED
                    _$player.jPlayer('play');
                }
                else {
                    // requeue current file
                    playFile();
                }
                console.debug('Play');
            }
            else if ($(this).hasClass('pause')) {
                _$player.jPlayer('pause');
                console.debug('Pause');
            }
            else if ($(this).hasClass('prev')) {
                console.debug('Prev');
                // prev title, queue only if not playing
// TBD                nextTitle(-1, _$player.input.state !== 3);
            }
            else if ($(this).hasClass('next')) {
                console.debug('Next');
                // next title, queue only if not playing
// TBD                nextTitle(1, _$player.input.state !== 3);
            }
            else if ($(this).hasClass('open')) {
                Event.fire('selectPlaylist', Playlist.getPlaylist(_player_status['playlist-id'], 'create if not exists'));
            }
            else {
                var $this= $(this)
                Util.forEach(_player_status_types, function(type, status) {
                    if (type !== 'button') return // continue
                    if ($this.hasClass(status)) {
                        _player_status[status]= !_player_status[status];
                        _updatePlayerStatus();
                        if (status === 'shuffle') {
                            Event.fire('changedPlayersOrder', _player_status.shuffle ? 'random' : 'orig');
                        }
                        return true // break
                    }
                })
            }
            playerStatusTimer.start();
            return false;
        });

        $('#player .timeinfo').live('click', function() {
            for (var i= 0; i < _time_modes.length; i++) {
                var mode= 'time-mode-' + _time_modes[i];
                if ($(this).hasClass(mode)) {
                    _player_status['time-mode']= _time_modes[(i + 1) % _time_modes.length];
                    updateTimeMode();
                    _updatePlayerStatus();
                    return;
                }
            }
            // default to first time mode
            _player_status['time-mode']= _time_modes[0];
            updateTimeMode();
            _updatePlayerStatus();
        });

        $('#player .progressbar').slider({
            'max': _slider_max - 1,
            'slide': function(event, ui) {
                if (_$player) {
                    _$player.jPlayer('playHead', ui.value / _slider_max * 100);
                }
            },
        }).slider('disable');

        Event.add('setRating', function(uid, rating) {
            if (!_playlist) return;
            var item= _playlist.getItem(uid);
            if (item && item.setRating) {
                item.setRating(rating);
            }
        });

        Event.add('playItem', function(uid, playlist) {
            if (playlist) return setPlaylist(playlist, function() { play(uid); });
            play(uid);
        });

        Event.add('updatedListItem', function() {
            updateTimeMode();
            updateFileNum();
        });

    };

// ============================================================================
//      player_obj and player_obj-playlist related functions
// ============================================================================

    // queues new item
    var queueItem= function(uid) {
        _item_uid= uid;
        var item= getItem(uid);
        if (!item) return;

        _item_file_index= 0;

        _player_status['playlist-id']= _playlist.text('playlist_id');
        _player_status['item-uid']= _item_uid;
        _updatePlayerStatus(
            function () {
                Event.fire('updatedItem', item);
                Util.setHtml($('#player .info'), item.itemHtml());
                updateFileNum();
            }
        );
        _play_button_cache.play.removeClass('ui-state-disabled');
        Event.fire('activeItemChanged');
        return true;

    };

    // starts playing of current file
    var playFile= function() {
        var item= getItem(_item_uid);
        if (!item) return false;

        var file= item.get('play_files')[_item_file_index];
        if (!file) return false;

        _$player.jPlayer('setFile', _base_url + file.get('url'));
//        _$player.jPlayer('setFile', _base_url + '/0' + Math.floor(Math.random() * 9 + 1) + '.mp3');
        _$player.jPlayer('play')
        playerStatusTimer.start();

        file.updateLastPlayed(function() {
            item.invalidateDetails();
            updateFileNum();
        });
        return true;
    };

    var stop= function() {
        _$player.jPlayer('clearFile');

        _item_uid= null;
        _item_file_index= -1;
    };

    var getSortOrder= function() {return _player_status.shuffle ? 'random' : 'orig'}

    var nextTitle= function(dir, queue_only) {
        var item= getItem(_item_uid);
        if (!item) return stop();

        var item_files= item.get('play_files');

        _item_file_index+= dir;
        if (playFile()) return;

        var index= _playlist.getItemIndex(_item_uid, getSortOrder());
        if (index == null) return;

        var uid= _playlist.getUidByIndex(index + dir, getSortOrder());
        if (!uid && dir > 0) {

            // if end is reached, reshuffle if enabled
            if (_player_status.shuffle) _playlist.scramble();

            // ...restart playlist
            if (_player_status.repeat) {
                uid= _playlist.getUidByIndex(0, getSortOrder());
            }
        }
        if (uid) {
            if (queue_only) {
                queue(uid);
            }
            else {
                play(uid);
            }
        }
    }

    // update buttons of play ctrl
    var updatePlayerStatus= (function() {
        var $player=            $('#player');
        var $progressbar=       $('#player .progressbar');
        var progressbar_disabled= true;

        return function(stopped) {

            var updateProgress= function() {
                $progressbar.slider('value', _$player.jPlayer('getData', 'diag.playedPercentAbsolute') / 100 * _slider_max)
                var curTime= _$player.jPlayer('getData', 'diag.playedTime')
                var lenTime= _$player.jPlayer('getData', 'diag.totalTime')
                Util.setHtml($('#player .position'), Util.formatTime(curTime / 1000));
                Util.setHtml($('#player .length'),   Util.formatTime(lenTime / 1000));
                Util.setHtml($('#player .remain'),   Util.formatTime((lenTime - curTime) / 1000));
            };
            var enable_progress= function(enable) {
                if (enable){
                    if (progressbar_disabled) $progressbar.slider('enable');
                }
                else {
                    if (!progressbar_disabled) $progressbar.slider('disable');
                }
                progressbar_disabled= !enable;
            }

// console.log('diag.isPlaying', _$player.jPlayer('getData', 'diag.isPlaying'))
// console.log('diag.playedTime', _$player.jPlayer('getData', 'diag.playedTime'))
// console.log('diag.src', _$player.jPlayer('getData', 'diag.src'))
            if (stopped) {
                var was_playing= $player.attr('state') === 'playing';
                if (!was_playing) {
                    $player.attr('state', 'stopped');
                    Event.fire('activeItemChanged');
                }
                if (_item_uid) {
                    var play_next= false;
                    if (was_playing) {
                        if (_player_status['stop-after']) {
                            // try to get next playable file of the same item
                            var item= getItem(_item_uid);
                            if (item) play_next= item.get('play_files').length > _item_file_index + 1;
                        }
                        else {
                            play_next= true;
                        }
                    }
                    if (play_next) {
                        nextTitle(1);
                    }
                    else {
                        // on "stop-after" requeue current item
                        queue(_item_uid);
                        $progressbar.slider('value', 0);
                        $player.attr('state', 'paused');
                    }
                }
                enable_progress(false);
            }
            else if (_$player.jPlayer('getData', 'diag.isPlaying')) {
                $player.attr('state', 'playing');
                enable_progress(true);
            }
            else if (_$player.jPlayer('getData', 'diag.playedTime') > 0) {
                $player.attr('state', 'paused');
                enable_progress(true);
            }

            Util.forEach(_play_buttons, function(button) {
                var $b= _play_button_cache[button];
                if ($b.hasClass('ui-state-disabled')) {
                    if (!stopped) $b.removeClass('ui-state-disabled');
                }
                else {
                    if (stopped) $b.addClass('ui-state-disabled');
                }
            });

            // queue next timer event if playing
            if (_$player.jPlayer('getData', 'diag.isPlaying')) {
                updateProgress();
                playerStatusTimer.start();
            }
        };
    })();

    // start timer for update player status
    var playerStatusTimer= new Util.DelayedFunc(_player_status_timeout, updatePlayerStatus);

// ============================================================================
//      Init and Exports
// ============================================================================

    _init();

    return {
        setup: setup,
        play: play,
        getCurrentItem: function() {return getItem(_item_uid)},
    };


// ============================================================================
//      Prologue
// ============================================================================

    })();

});
