// ============================================================================
//     VLC Player Library
// ============================================================================

jQuery(function($, undefined) {

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
    var _file_url= 'file://';
    var _encode_url= null;

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

    var _play_button_cache= {};

    // add regular play buttons (play, prev, next...)
    Util.forEach(_play_buttons, function(button) {_play_button_cache[button]= $('.playctl .' + button)})

    // add player status buttons (repeat, shuffle...)
    Util.forEach(_player_status_types, function(type, button) {
        if (type !== 'button') return // continue
        _play_button_cache[button]= $('.playctl .' + button);
    })

    // wrapper for jPlayer calls to respect jPlayer.ready() function
    // queues all calls to player before ready() was called
    var jPlayer= (function() {
        var $jPlayer= $('#jquery_jplayer')
        var _jPlayer= $jPlayer.jPlayer
        var fnDataQueue= []
        var ready= false

        // initialize player
        $jPlayer.jPlayer( {
            swfPath: '/static/',
            supplied: 'oga',
//            supplied: 'oga,mp3',
//            supplied: 'mp3',
//            solution: 'flash',
            solution: 'html,flash',
            preload: 'auto',
            errorAlerts: false,
            warningAlerts: false,
            cssSelectorAncestor: '#dummyplayer',
        })

        var set= function() {
            // console.log('jPlayer', arguments)
            if (ready) return _jPlayer.apply($jPlayer, arguments)
            // return undefined for getData calls unless ready
            if (arguments[0] === 'getData') return undefined
            // queue function
            fnDataQueue.push(arguments)
            // return an empty object with this function to allow jPlayer(...).jPlayer(...)
            return jPlayer
        }

        var bind= function(name, fn) {
            $jPlayer.bind($.jPlayer.event[name], function(ev) {fn(ev.jPlayer)})
            return jPlayer
        }

        var unbind= function(name) {
            $jPlayer.unbind($.jPlayer.event[name])
            return jPlayer
        }

        var playing= false
        var paused= false
        var playerStatus= {};
        bind('ready', function (ev) {
            playerStatus= ev
            ready= true
            Util.forEach(fnDataQueue, function(fnData) {_jPlayer.apply($jPlayer, fnData)})
            fnDataQueue= []
        })
        bind('play',  function() {playing= true; paused= false})
        bind('pause',  function() {playing= false; paused= true})
        bind('ended',  function() {playing= false; paused= false})

        return {
            set:    set,
            bind:   bind,
            unbind: unbind,
            playing: function() {return playing},
            paused: function() {return paused},

            play:  function() {set('play')},
            pause: function() {set('pause')},
            stop:  function() {set('stop')},
        }
    })()


    var getItem= function(uid) {
        if (_playlist) return _playlist.getItem(uid);
        return null;
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

    var setup= function(status, file_url, encode_url, fn_getPlaylist, fn_loadPlaylist) {
        var buildUrl= function(url) {
            if (url == null) return null;
            var protocol= 'http';
            var host= window.location.hostname;
            var port= undefined;
            var parts= url.split('://');
            if (parts.length > 1) {
                protocol= parts.shift() || protocol;
            }
            parts= parts[0].split(':');
            if (parts.length > 1) {
                port= parts.pop();
                parts= [parts.join(':')];
            }
            if (parts[0] !== '') {
                host= parts[0];
            }
            if (port) {
                if (port == 80 && protocol == 'http' || port == 443 && protocol == 'https') {
                    port= '';
                }
                else {
                    port= ':' + port;
                }
            }
            return protocol + '://' + host + port
        }

        _file_url= buildUrl(file_url);
        _encode_url= buildUrl(encode_url);
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
                queue(item_uid);
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
        jPlayer.set('volume', 1)
        jPlayer.bind('ended', playerStopped)
        jPlayer.bind('timeupdate', playerProgress)

        var playPause= function() {
            if (jPlayer.playing()) {
                jPlayer.pause();
                $('#player').attr('state', 'paused');
                console.debug('Pause');
                return
            }
            var fnFinish= function() {
                $('#player').attr('state', 'playing');
                playerStarted()
            }
            if (jPlayer.paused()) { // PAUSED
                jPlayer.play();
                console.debug('Play (unpaused)');
                fnFinish()
            }
            else {
                // requeue current file
                playFile(function() {
                    console.debug('Play')
                    fnFinish()
                });
            }
            return false
        }

        // manage player's buttons
        $('ul.playctl li').live('click', function() {
            if ($(this).hasClass('ui-state-disabled')) return false;
            if ($(this).hasClass('play-pause')) {
                playPause()
            }
            else if ($(this).hasClass('prev')) {
                console.debug('Prev');
                // prev title, queue_only if not playing
                nextTitle(-1, playerStatus == 'pause');
            }
            else if ($(this).hasClass('next')) {
                console.debug('Next');
                // next title, queue_only if not playing
                nextTitle(1, playerStatus == 'pause');
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

        // catch spaces to toggle play/pause
        $('html').keydown(function(e) {
            if (e.keyCode === 32) {
                if (!$(e.target).is('input') && !$(e.target).is('textarea')) {
                    return playPause()
                }
            }
        })

        $('#player .progressbar').slider({
            'max': _slider_max - 1,
            'slide': function(event, ui) {
                jPlayer.set('playHead', ui.value / _slider_max * 100);
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
            stop()
            if (playlist) return setPlaylist(playlist, function() { play(uid) })
            play(uid)
        })

        Event.add('updatedListItem', function() {
            updateTimeMode();
            updateFileNum();
        });

    };

// ============================================================================
//      player_obj and player_obj-playlist related functions
// ============================================================================

    // queues new item (updates player's display with new item)
    var queue= function(uid) {
        _item_uid= uid
        var item= getItem(uid)
        if (!item) return stop()

        _item_file_index= 0

        _player_status['playlist-id']= _playlist.text('playlist_id')
        _player_status['item-uid']= _item_uid
        _updatePlayerStatus(
            function () {
                Event.fire('updatedItem', item)
                Util.setHtml($('#player .info'), item.itemHtml())
                updateFileNum();
            }
        )
        _play_button_cache.play.removeClass('ui-state-disabled')
        Event.fire('activeItemChanged')
        return true
    }

    // starts playing of current file
    var playFile= function(fnFinish) {
        var item= getItem(_item_uid)
        if (!item) {
            stop()
            if (fnFinish) fnFinish(false)
            return
        }

        var file= item.get('play_files')[_item_file_index]
        if (!file) {
            stop()
            if (fnFinish) fnFinish(false)
            return
        }

        var filename= file.get('url')
        Util.doJsonRequest(
            'prepareFile',
            {
                file: filename,
                format: 'oga',
            },
            null,
            function(json) {
                jPlayer.set('setMedia', {
                    oga: (json.encoding == 1 ? _encode_url : _file_url) + json.path,
                })
//              jPlayer('setFile', _base_url + '/0' + Math.floor(Math.random() * 9 + 1) + '.mp3')
                jPlayer.play()

                file.updateLastPlayed(function() {
                    item.invalidateDetails()
                    updateFileNum()
                })
                $('#player').attr('state', 'playing')
                playerStarted()
                if (fnFinish) fnFinish(true)
            }
        )
    }

    var play= function(uid) {
        queue(uid)
        playFile()
    }

    var stop= function() {
        jPlayer.stop()

        _item_uid= null
        _item_file_index= -1
    }

    var getSortOrder= function() {return _player_status.shuffle ? 'random' : 'orig'}

    var nextTitle= function(dir, queue_only) {
        // remember current item - playFile() will call stop() on failure and reset _item_uid
        var uid= _item_uid
        var item= getItem(uid)
        if (!item) return stop()

        var item_files= item.get('play_files')

        _item_file_index+= dir
        playFile(
            function(success) {
                if (success) return

                var index= _playlist.getItemIndex(uid, getSortOrder())
                if (index == null) return

                uid= _playlist.getUidByIndex(index + dir, getSortOrder())
                if (!uid && dir > 0) {

                    // if end is reached, reshuffle if shuffle mode is enabled
                    if (_player_status.shuffle) _playlist.scramble()

                    // ...restart playlist if repeat is enabled
                    if (_player_status.repeat) {
                        uid= _playlist.getUidByIndex(0, getSortOrder())
                    }
                }
                if (uid) {
                    queue(uid)
                    if (queue_only) return
                    playFile()
                }
            }
        )

    }

    var enableProgressBar= (function() {
        var enabled= false
        var $progressbar= $('#player .progressbar')

        return function(enable) {
            if (enable !== enabled) {
                $progressbar.slider(enable ? 'enable' : 'disable')
                enabled= enable
            }
        }
    })()

    var playerStarted= function() {
        enableProgressBar(true)
        Util.forEach(_play_buttons, function(button) {
            var $b= _play_button_cache[button]
            if ($b.hasClass('ui-state-disabled')) {
                $b.removeClass('ui-state-disabled')
            }
        })
    }

    var playerStopped= function() {
        var $player= $('#player')

        var was_playing= $player.attr('state') === 'playing'

        $player.attr('state', 'stopped')
        Event.fire('activeItemChanged')

        enableProgressBar(false)
        Util.forEach(_play_buttons, function(button) {
            var $b= _play_button_cache[button]
            if (! $b.hasClass('ui-state-disabled')) {
                $b.addClass('ui-state-disabled')
            }
        })

        if (_item_uid) {
            if (was_playing) {
                if (_player_status['stop-after']) {
                    // try to get next playable file of the same item
                    var item= getItem(_item_uid);
                    if (item && item.get('play_files').length > _item_file_index + 1) {
                        nextTitle(1)
                        return
                    }
                }
                else {
                    nextTitle(1)
                    return
                }
            }
            // requeue current item and pause
            queue(_item_uid)
            $player.attr('state', 'paused')
            return
        }

    }

    var playerProgress= (function() {
        var $progressbar= $('#player .progressbar')
        var lastData= {}

        return function(ev) {
            var playedPercentAbs= ev.status.currentPercentAbsolute;
            var timePlayed= ev.status.currentTime;
            var timeTotal= ev.status.duration;
            // fix for realtime ogg-streams
            if (timeTotal == 0 || isNaN(timeTotal)) {
                if (_item_uid != lastData['item_uid'] || _item_file_index != lastData['file_index'] || !lastData['file_length']) {
                    var item= getItem(_item_uid)
                    if (item) {
                        var file= item.get('play_files')[_item_file_index]
                        if (file) lastData['file_length']= file.get('length');
                    }
                }
                timeTotal= lastData['file_length'];
            }

            var curData= {
                position: parseInt(timePlayed),
                length:   parseInt(timeTotal),
                remain:   parseInt(timeTotal - timePlayed),
            }

            var updated= false

            for (var key in curData) {
                if (curData[key] === lastData[key]) continue
                Util.setHtml($('#player .' + key), Util.formatTime(curData[key]))
                updated= true
            }

            if (!updated) return

            $progressbar.slider('value', playedPercentAbs / 100 * _slider_max)

            lastData= curData
        }
    })();

// ============================================================================
//      Init and Exports
// ============================================================================

    _init();

    return {
        setup: setup,
        getCurrentItem: function() {return getItem(_item_uid)},
    }

    })()

})
