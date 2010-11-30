
// ============================================================================
//     Playlist Module
// ============================================================================

jQuery(function($, undefined) {

    VD.Playlist= (function() {

// ============================================================================
//      Import Modules
// ============================================================================

    var Event= VD.Event;
    var Util= VD.Util;
    var Item= VD.Item;

// ============================================================================
//      Basic utility functions
// ============================================================================

    var _playlists= {};
    var _playlist_type_order= [ 'real', 'virtual', 'search' ];
    var _search_playlists_count= 5;

    var _init= function() {
        Event.add('updatedItem', function(item) {
            Util.forEach(_playlists, function(playlists) {
                Util.forEach(playlists, function(playlist) {
                    playlist.updateItem(item)
                })
            })
        });
    };

// ============================================================================
//      playlist functions
// ============================================================================

    var createPlaylist= function(name) {
        Item.createPlaylist(name, function(new_playlist) {
            var type= new_playlist.text('playlist_type');
            if (!_playlists[type]) _playlists[type]= [];
            _playlists[type].push(new_playlist);
            Event.fire('playlistListChanged');
            Event.fire('playlistCreated', new_playlist);
        });
    };

    var renamePlaylist= function(playlist, newname) {
        playlist.rename(newname, function() {
            Event.fire('playlistListChanged');
        });
    };

    var deletePlaylist= function(playlist) {
        playlist.destroy(function() {
            Util.forEach(_playlists, function(playlists) {
                Util.forEach(playlists, function(pl, i) {
                    if (pl === playlist) {
                        delete playlists[i];
                        Event.fire('playlistListChanged');
                        return false // break
                    }
                })
            })
        });
    };

    var addToPlaylist= function(playlist, plays) {
        playlist.addItems(plays);
    };

    var removeFromPlaylist= function(playlist, plays) {
        playlist.removeItems(plays);
    };

    var parsePlaylists= function(playlists) {
        // preserve search playlists
        _playlists= {
            'search': _playlists.search,
        };
        Util.forEach(playlists, function(playlist) {
            var type= playlist.text('playlist_type');
            if (!_playlists[type]) _playlists[type]= [];
            _playlists[type].push(playlist);
        });
    }

    var getPlaylist= function(playlist_id, create_if_not_exists) {
        if (!playlist_id) return null;
        var pl= Util.forEach(_playlists, function(playlists) {
            return Util.forEach(playlists, function(playlist) {
                if (playlist.text('playlist_id') === playlist_id) return playlist;
            })
        })
        if (pl !== undefined) return pl
        var playlist_parts= playlist_id.split(':', 2);
        if (playlist_parts[0] === 'search') {
            var playlist= Item.create({
                'type': 'playlist',
                'name': 'Suche "' + playlist_parts[1] + '"',
                'playlist_id': playlist_id,
            });
            if (create_if_not_exists) {
                if (!_playlists.search) _playlists.search= [];
                _playlists.search.push(playlist);
                _playlists.search= _playlists.search.slice(-_search_playlists_count);
                Event.fire('playlistListChanged');
            }
            return playlist;
        }
    }

// ============================================================================
//      retrieving playlists and fill select field
// ============================================================================
    var getPlaylists= function(fn) {
        Util.doJsonRequest('getplaylists',
            {},
            function(js_data) {
                var playlists= Util.map(js_data, function(data) {return Item.create(data)})
                parsePlaylists(playlists);
                return playlists;
            },
            fn
        );
    };

    // return list of playlists sorted by type
    var getSortedPlaylists= function() {
        var types= []
        Util.forEach(_playlists, function(type) {types.push(type)})
        var playlist_types= _playlist_type_order.concat(types);
        var pt_done= {};
        var list= [];
        Util.forEach(playlist_types, function(type) {
            if (pt_done[type]) return;
            pt_done[type]= 1;
            if (_playlists[type]) list= list.concat(_playlists[type]);
        });
        return list;
    };

// ============================================================================
//      Init and Exports
// ============================================================================

    _init();

    return {
        getPlaylist: getPlaylist,
        getPlaylists: getPlaylists,
        getSortedPlaylists: getSortedPlaylists,
        createPlaylist: createPlaylist,
        renamePlaylist: renamePlaylist,
        deletePlaylist: deletePlaylist,
        addToPlaylist: addToPlaylist,
        removeFromPlaylist: removeFromPlaylist,
    };

// ============================================================================
//      Prologue
// ============================================================================

    })();

});
