
jQuery(function($) {

// ============================================================================
//      Import Modules
// ============================================================================

    var Util= VD.Util;
    var Event= VD.Event;
    var Item= VD.Item;
    var Playlist= VD.Playlist;
    var Player= VD.Player;
    var Listview= VD.Listview;

// ============================================================================
//      Date/Time Utils
// ============================================================================

    var timeStrToDateObj= function(timeStr, cmpTime) {
        var re= timeStr.match(/^(....)(..)(..)(..)(..)(..)$/);
        if (re) return new Date(Date.UTC(re[1], re[2], re[3], re[4], re[5], re[6]));
        return null;
    };

    var fmtDateObj= function(d, cmpDate) {
        var f2= function(i) {return i < 10 ? '0' + i : i}
        var ymd= d.getFullYear() + '-' + f2(d.getMonth() + 1) + '-' + f2(d.getDate())
        var hms= f2(d.getHours()) + ':' + f2(d.getMinutes()) + ':' + f2(d.getSeconds());
        if (cmpDate) {
            var cmpYMD= d.getFullYear() + '-' + f2(d.getMonth() + 1) + '-' + f2(d.getDate());
            if (ymd === cmpYMD) return hms;
        }
        return ymd + ' ' + hms;
    };

    var fmtTime= function(timeObj) {
        var start= timeStrToDateObj(timeObj.start);
        var end= timeStrToDateObj(timeObj.end);
        return fmtDateObj(start) + ' ... ' + fmtDateObj(end, start);
    };
    

// ============================================================================
//      Commands
// ============================================================================

    var cmds= {
        'setrating': function (obj, params) {
            var rating= params.rating;
            var uid= params.uid;
            Event.fire('setRating', uid, rating);
            return false;
        },
        'play': function (obj, params) {
            var uid= params.uid;
            Event.fire('playItem', uid, obj);
            return false;
        },
        'setdetails': function (obj, params) {
            var uid= params.uid;
            var hoerdat_id= params.hoerdat_id;
            return Listview.setDetails(uid, hoerdat_id);
        },
        'editfile': function (obj, params) {
            var uid= params.uid;
            var md5= params.md5;
            return Listview.editFile(obj, uid, md5);
        },
        'savefilelist': function(obj, params) {
            var uid= params.uid;
            return Listview.saveFilelist(uid);
        },
        'load-target-playlist': function(obj, params) {
            return Listview.loadTargetPlaylist();
        },
    };

    var processClick= function(obj, href) {
        var paramsl= href.substr(1).split(/\|/);
        var cmd= paramsl.shift();
        var cmdFn= cmds[cmd];
        if (!cmdFn) {
            console.warn('Command "' + cmd + '" not defined');
            return true;
        }

        var params= {};
        while (paramsl.length) {
            var keyvalue= paramsl.shift().split(/\=/, 2);
            params[keyvalue[0]]= decodeURIComponent(keyvalue[1]);
        }

        cmdFn($(obj), params);  //      return cmdFn(params) ???
        return false;
    };

// ============================================================================
//      Live Event Handlers
// ============================================================================

    // process generic commands
    // TODO: Move to vd.util.js
    $('a').live('click', function() {
        var href= $(this).attr('href');
        if (!href) return true;

        console.debug("Clicked:", href);

        // Not an internal link, pass on to browser
        if (href.substr(0, 1) !== '#') return true;

        return processClick(this, href);
    });

    // hover handling for itemlist entries
    $('.marquee').live('mouseover', function(event) {
        $(this).marquee('on');
    });

    $('.marquee').live('mouseout', function() {
        $(this).marquee('off');
    });

// ============================================================================
//      playlist related functions
// ============================================================================

    // returns items in viewed order
    var getSortOrder= function() {
        return Util.filter(
            Util.map(
                $('#itemlist .iteminfo').get(),
                function(elem) {return Listview.getItem($(elem).attr('uid'))}
            ),
            function(item) {return item}
        )
    }

// ============================================================================
//      Init
// ============================================================================

    // Chrome workaround:
    // 'bla[key=value]' doesn't refresh the screen. Must be rewritten to 'bla.attr-key-value'

    if ( navigator.userAgent.toLowerCase().indexOf('chrome') >= 0 ) {
        var oldAttrFn= $.prototype.attr;

        var refreshHack= new Util.DelayedFunc(10, function() {
//            $('html').removeClass('dummy').addClass('dummy');
            $('html').removeClass('dummy');
        });

        $.fn.attr = $.prototype.attr= function( name, value, type ) {
            refreshHack.start();
            return oldAttrFn.call(this, name, value, type);
        };
    }

    $(function() {
        $('html').attr('mode', 'player');
        // fill player witch empty info
        Util.setHtml($('#player .info'), (Item.create()).itemHtml());
        Util.doJsonRequest(
            'getglobaldata',
            {},
            null,
            function(js_data) {
                Listview.initWui(
                    {
                        source: js_data['last-playlist-id'],
                    },
                    function() {return Player.setup(
                        js_data['player-status'],
                        js_data.baseurl,
                        function(id) {return Playlist.getPlaylist(id, 'create if not exists')},
                        Util.loadPlaylist
                    )}
                )
            }
        )
        // catch spaces to toggle play/pause
        $('html').keydown(function(e) {
            if (e.keyCode === 32) {
                if (!$(e.target).is('input') && !$(e.target).is('textarea')) {
                    $('.playctl .pause').trigger('click');
                    return false;
                }
            }
        });
        $('#edit-item').dialog({
            'autoOpen': false,
            'modal': true,
            'resizable': false,
            'width': 600,
            'maxHeight': 500,
            'position': 'top',
        });
        $('#dialog-iteminfo').dialog({
            'autoOpen': false,
            'modal': false,
            'resizable': false,
            'draggable': false,
            'width': 500,
            'height': 270,
            'position': [0, 0],
            'close': function() {
                $(this).find('.iteminfo').removeClass('sticky');
            }
        });
        $('#edit-playlist').dialog({
            'autoOpen': false,
            'modal': true,
        });
    });


});
