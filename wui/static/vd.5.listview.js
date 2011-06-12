
// ============================================================================
//     Itemview handling Library
// ============================================================================

jQuery(function($, undefined) {

    VD.Listview= (function() {

// ============================================================================
//      Import Modules
// ============================================================================

    var Event= VD.Event;
    var Util= VD.Util;
    var Item= VD.Item;
    var Player= VD.Player;
    var Playlist= VD.Playlist;

// ============================================================================
//      Basic utility functions
// ============================================================================

    var _playlists= {
        player: null,
        target: null,
        source: null,
    };
    var _playlist_order= {};
    var _playlist_tab= 'player';

    var _visible_uids= null;

    var _hoerdat_result= {};

    // timeout till next player status update
    var _tooltip_timeout= 1000;
    var _search_update_timeout= 1000;

    // update cche for some elements
    var $dialog_iteminfo= $('#dialog-iteminfo');
    
// ============================================================================
//      TBD
// ============================================================================

    var _title= function(title) {return title || 'unbenannt'}

    // show tooltip on hovering item
    var showItemTooltip= new Util.DelayedFunc(_tooltip_timeout, function(event) {
        if ($dialog_iteminfo.dialog('isOpen') && $dialog_iteminfo.hasClass('sticky')) return;

        Util.setHtml($dialog_iteminfo, '<div class="info-head">lade Info...</div>');

        var uid= $(event.target).parents('.iteminfo').attr('uid');
        var item= getItem(uid);
        if (!item) return;

        var _showTooltip= function(title, content) {
            Util.setHtml($dialog_iteminfo, content.render());
            $dialog_iteminfo.dialog('option', 'title', _title(title));
            $dialog_iteminfo.dialog('open');
            var $play_button= $('#dialog-iteminfo-play');
            if ($play_button.length < 1) {
                $play_button= $('<span id="dialog-iteminfo-play" class="ui-icon ui-icon-play"></span>');
                $dialog_iteminfo.parent('.ui-dialog').find('.ui-dialog-title').before($play_button);
            }
            $play_button.unbind('click').bind('click', function() { Event.fire('playItem', uid, getCurrentPlaylist()) });
        };

        if ($(event.target).hasClass('file-count')) {
            var files= item.get('files');
            var content= new Util.Html();
            Util.forEach(files, function(file) {
                var classes= ['info-file'];
                if (file.int('play_order') < 0) classes.push('inactive');
                content.add('<div class="' + classes.join(' ') + '">', '</div>').add(file.text('name') + ' - ' + Util.formatTime(file.int('length')));
            });
            _showTooltip('Dateien von "' + _title(item.text('title')) + '"', content);
        }
        else {
            // build items info in tooltip
            item.getDetails(function(item) {
                var content= new Util.Html();
                var genres= item.text('genres');
                if (genres.length) {
                    content.add('<div class="info-genres">', '</div>').add(genres);
                }
                content.add('<div>')
                var div= content.add('<div class="info-head">', '</div>');
                div.add('<span class="authors">', '</span>').add(item.text('authornames'));
                content.add('<div class="info-desc">', '</div>').add(item.html('description'));
                _showTooltip(item.text('title'), content);
            });
        }
    });

    var updateSearch= new Util.DelayedFunc(_search_update_timeout, function(ev) {
        var playlist= Playlist.getPlaylist('search:' + $('#search').val());
        $('#playlistselect')[0].selectedIndex= -1;
        loadViewPlaylist(playlist);
    });

    var setDetails= function (uid, hoerdat_id) {
        var selected_items= [];

        // get all selected items, make sure current item is first one (if selected)
        $('.itemlist-entry.selected').each(function() {
            var tmp_uid= $(this).attr('uid');
            var item= getItem(tmp_uid)
            if (tmp_uid === uid) {
                selected_items.unshift(item);
            }
            else {
                // only add files
                if (item.type === 'file') selected_items.push(item);
            }
        });

        // if edited item is not selected (ie. is not first item), only update this item
        if (selected_items.length === 0 || selected_items[0].get('uid') !== uid) {
            selected_items= [ getItem(uid) ];
        }

        var data= hoerdat_id ? _hoerdat_result[hoerdat_id].rawData() : null;

        var old_item= selected_items.shift();

        old_item.setDetails(data, function(item) {
            replaceItemsListEntry(old_item.text('uid'), [item]);

            var new_play_id= item.text('play_id');

            Util.forEach(selected_items, function(old_item) {
                old_item.setExtendedDetails({new_play_id: new_play_id}, function(items) {
                    $listSelector('.itemlist-entry[uid="' + old_item.text('uid') + '"]').remove();
                    Util.forEach(_playlists, function(playlist) {
                        if (playlist) playlist.removeItems([old_item])
                    });
                })
            });
        });
    };

    // returns jquery selector for given elements in tab's (or current) playlistview
    var $listSelector= (function() {
        var cache= {};
        return function(elements, tab) {
            if (!tab) tab= _playlist_tab;
            var $sel= cache[tab];
            if (!$sel) $sel= cache[tab]= $('#list-' + tab);
            if (!elements) return $sel;
            return $sel.find(elements);
        };
    })();

    // TODO: replace params
    var applyRatingFilter=  function(params) {
        var $body= $('#body');
        if (params.remove_all) {
            $body.attr('filter', '');
            $('#ratingfilter').slider('values', 0, 0)
                .slider('values', 1, 10);
            return;
        }
        if (params.add) {
            addAttr($body, 'filter', params.add);
        }
    };

    var editFile= function (obj, uid, md5) {
        var data= getItem(uid);
        var file_data= null;
        var files= data.get('files');
        Util.forEach(files, function(file) {
            if (file.text('md5') === md5) {
                file_data= file;
                return true // break
            }
        })
        if (! file_data) return;
        var $filelist= $(obj).parents('.filelist');
        $filelist.find('.edit').removeClass('edit');
        $(obj).addClass('edit');
        var $content= $filelist.next();
        var content_form= new Util.Html('<form>', '</form>');
        var content_table= content_form.addTable();
        var disabled= '';
        switch (data.type) {
            case 'play':
                content_table.addRow([
                    '<input type="checkbox" id="editfile-remove-play-id" name="remove-play-id"/>',
                    '<label for="editfile-remove-play-id">Datei vom Hoerspiel trennen</label>',
                ]);
                disabled= ' disabled="1"';
                break;
            case 'file':
                break;
        }
        content_table.addRow([
            '<label for="editfile-play-id">Gruppieren mit:</label>',
            '<select id="editfile-play-id" name="play-id"' + disabled + '/>',
        ]);
        content_table.addRow([
            '<label for="editfile-title">Titel:</label>',
            '<input type="text", id="editfile-title" name="title" size="40"' + disabled + '/>',
        ]);
        content_table.addRow([
            '<label for="editfile-addition">Zusatz:</label>',
            '<input type="text", id="editfile-adddition" name="addition" size="40"/>',
        ]);
        content_table.addRow([
            '<label for="editfile-part-num">Teil:</label>',
            '<input type="text", id="editfile-part-num" name="part-num" size="3"/>' +
            '<label for="editfile-part-count"> von </label>' +
            '<input type="text", id="editfile-part-count" name="part-count" size="3"/>',
        ]);
        content_form.add('<input type="submit" name"change" value="&Auml;ndern">')
        content_form.render($content);
        var $content_form= $content.find('form');

        $content_form.find('input[name="remove-play-id"]').change(function() {
            if ($(this).val()) {
                $content_form.find('select[name="play-id"]').removeAttr('disabled');
                $content_form.find('input[name="title"]').removeAttr('disabled');
            }
            else {
                $content_form.find('select[name="play-id"]').attr('disabled', '1');
                $content_form.find('input[name="title"]').attr('disabled', '1');
            }
        })
        $content_form.find('select[name="play-id"]').change(function() {
            if ($(this).val()) {
                $content_form.find('input[name="title"]').attr('disabled', '1');
            }
            else {
                $content_form.find('input[name="title"]').removeAttr('disabled');
            }
        })
        $content_form.find('input[name="title"]').val(file_data.text('title'));
        var $select= $content_form.find('select[name="play-id"]');
        Util.setHtml($select, '<option value="" selected>eigenes H&ouml;rspiel</option>');
        var done_plays= {};
        var items= getCurrentPlaylist().items();
        if (Util.forEach(items, function(item) {
            if (item.type !== 'play' || item.get('hoerdat_id')) return // continue
            var play_id= item.get('play_id');
            if (done_plays[play_id]) return true // break
            done_plays[play_id]= 1;
            $select.append('<option value="' + play_id + '">' + _title(item.text('title')) + '</option>');
        })) return
        $content_form.find('input[name="addition"]').val(file_data.text('addition'));
        $content_form.find('input[name="part-num"]').val(file_data.text('part_num'));
        $content_form.find('input[name="part-count"]').val(file_data.text('part_count'));
        $content_form.submit(function() { setFileDetails(uid, md5, $content_form); return false; });
    };

    var saveFilelist= function(uid) {
        var item= getItem(uid);
        var files= item.get('files');
        var order= {};
        Util.forEach(files, function(file) {
            order[file.text('md5')]= file.int('play_order');
        });

        item.setFilesOrder(order, function(item) {
            Util.setHtml($('.itemlist-entry[uid="' + uid + '"]'), item.itemHtml());
            Util.updateMarquees();
            fillFileList(uid);
        });
    };

// ============================================================================
//      Playlists functions
// ============================================================================

    // select or deselect an entry
    var selectEntries= function($entries) {
        for (var i= 0; i < $entries.length; i++) {
            var $entry= $($entries[i]);
            var item= getItem($entry.attr('uid'));
//            if (item.type !== 'play') return;
            $entry.addClass('selected');
        }
        updateSelectedEntries();
    };

    var deselectEntries= function($entries) {
        $entries.find('.ui-left .select').each(function() {this.checked= false});
        $entries.removeClass('selected');
    };
    var updateSelectedEntries= function() {
        $('.itemlist-entry.selected .ui-left .select').each(function() {this.checked= true})
    }

    var setPlaylist= function(tab, playlist) {
        // clear old playlist if not opened in other tab
        var old_playlist= getCurrentPlaylist();
        // disabled for tests
        if (false && old_playlist) {
            var found= false;
            for (var tab in _playlists) {
                if (_playlist_tab !== tab && old_playlist === _playlists[tab]) found= true;
            }
            if (!found) {
                console.log('Clearing Playlist', old_playlist.text('playlist_id'));
                old_playlist.clear();
            }
        }
        _playlists[tab]= playlist;
    }

    // loads playlist and views it
    var loadViewPlaylist= function(playlist, tab) {
        clearCache();
        if (!tab) tab= _playlist_tab;
        setPlaylist(tab, playlist);

        if (tab === _playlist_tab) updateDocumentTitle();
        $listSelector(null, tab).empty();

        if (!playlist) return;

        playlist.load(function() {
            if (tab !== 'player') _playlist_order[tab]= 'orig';
            viewItemlist(tab);
        });
    };

    // views given playlist
    var viewItemlist= function(tab) {
        if (!tab) tab= _playlist_tab;
        var playlist= _playlists[tab];

        Util.setHtml($listSelector(null, tab), '<div class="itemlist"></div>');

        if (!playlist) return;

        var html= new Util.Html();
        var sortedItems= playlist.sortedItems(_playlist_order[tab] || 'orig');
        Util.forEach(sortedItems, function(item) {html.add(createListEntry(item, true))})
        Util.setHtml($listSelector('.itemlist', tab), html.render());

        if (tab === 'target' && playlist.text('playlist_type') === 'real') {
            $listSelector('.itemlist', tab).sortable({
                'axis': 'y',
                'items': '.itemlist-entry',
                'handle': '.iteminfo',
                'tolerance': 'pointer',
                'distance': 10,
            });
        }

        if (tab === _playlist_tab) {
            clearCache();
            onMainScroll.now();
        }
        Event.fire('activeItemChanged', true);
    };

    var clearCache= function() {
        _visible_uids= null;
    };

    var getVisibleUids= function() {
        if (!_visible_uids) {
            _visible_uids= [];
            $listSelector('.itemlist .itemlist-entry').each(function() {
                if ($(this).css('display') !== 'none') {
                    _visible_uids.push($(this).attr('uid'));
                }
            });
        }
        return _visible_uids;
    };

    var onMainScroll= new Util.DelayedFunc(10, function(ev) {
        if (!getCurrentPlaylist()) return;

        var top= $('#main').offset().top - $listSelector('.itemlist').offset().top;
        if (top < 0) top= 0;

        // the height of a single item
        var height= $listSelector('.itemlist .itemlist-entry:first-child').outerHeight();

        // do one element more than actually fits in
        var remain_height= $('#main').height() + height;

        var uids= getVisibleUids();

        // first visible starts with 1
        var first_visible= Math.floor(top / height);
        var list_updated= false;

        for (var i= first_visible; i < uids.length && remain_height > 0; i++) {
            var uid= uids[i];
            var $entry= $listSelector('.itemlist .itemlist-entry[uid="' + uid + '"]');
            if ($entry.hasClass('empty')) {
                list_updated= true;
                var uid= $entry.attr('uid');
                // console.log(uid)
                var item= getItem(uid);
                if (!item) continue;
                Util.setHtml($entry, item.itemHtml());
                $entry.removeClass('empty');
            }
            remain_height-= height;
        }

        if (list_updated) {
            Util.updateMarquees();
            updateSelectedEntries();
        }
    });

    for (var tab in _playlists) {
        $listSelector(null, tab).scroll(onMainScroll.startFn);
    }
    $(window).resize(onMainScroll.startFn);

    // updates highlighting of currently played item
    var highlightActiveEntry= (function() {
        var current_uid= '';
        return function(force) {
            var cur_item= Player.getCurrentItem();
            if (!cur_item) return;

            var uid= cur_item.text('uid');

            // current item already selected
            if (!force && current_uid === uid) return;

            var $entry= $('#list-player .itemlist-entry[uid="' + uid + '"]');

            // remove "playing" from hilighted selected item
            $('#list-player .playing').removeClass('playing');
            if ($entry.length) $entry.addClass('playing');
            current_uid= uid;
        };
    })();

// ============================================================================
//      functions to view and update item's data
// ============================================================================

    // queries hoerdat and displays result
    var searchHoerdat= function(uid, form) {
        var title= $(form).find('input[name="title"]').attr('value');
        var author_name= $(form).find('input[name="author_name"]').attr('value');
        var author_given= $(form).find('input[name="author_given"]').attr('value');
        var result= $(form).next('.result')[0];

        _hoerdat_result= {};
        $(result).empty();
        $(result).append('<p>Suche...</p>');
        Util.doJsonRequest( 'queryhoerdat',
            { 
                'title': title,
                'author_name': author_name,
                'author_given_name': author_given
            },
            null,
            function(js_data) {
                $(result).empty();
                if (js_data.length === 0) {
                    $(result).append('<p>Keine Ergebnisse</p>');
                    return;
                }
                var items= Util.map(js_data, function(data) {return Item.create(data)})

                Util.forEach(items, function(item, i) {
                    var resultlinks= new Util.Html('<div class="right">', '</div>');

                    Util.forEach(items, function(link_item, i) {
                        var container= resultlinks;
                        if (item !== link_item) container= resultlinks.add('<a href="#result' + i + '">', '</a>');
                        container.add(parseInt(i, 10) + 1);
                        resultlinks.add(' ');
                    })

                    var hoerdat_id= item.text('hoerdat_id');
                    _hoerdat_result[hoerdat_id]= item;
                    $(result).append('<hr/>');
                    var div= new Util.Html('<div class="resultheader">', '</div>');
                    div.add('<a name="result' + i + '"/>');
                    div.add('<div class="left">', '</div>').add('<a href="' + Util.buildCmdRef('setdetails', 
                        {
                            'hoerdat_id': hoerdat_id,
                            'uid': uid,
                        }
                    ) + '">', '</a>').add('&Uuml;bernehmen');
                    div.addItem(resultlinks);
                    div.add('<div class="clearall">', '</div>');
                    $(result).append(div.render());
                    $(result).append('<div class="resultbody">' + buildItemDetails(item, getItem(uid)) + '</div>');
                })
            }
        );
    };

    // updates file's data
    var setFileDetails= function(uid, md5, form) {
        var data= {
            'new_play_id':      form.find('select[name="play-id"]').val() || null,
            'remove_play_id':   form.find('input[name="remove-play-id"]:checked').val() || 0,
            'title':            form.find('input[name="title"]').val() || null,
            'part_num':         form.find('input[name="part-num"]').val(),
            'part_count':       form.find('input[name="part-count"]').val(),
            'addition':         form.find('input[name="addition"]').val()
        };

        var file= null;
        var pre_item= getItem(uid);
        if (!pre_item) return;
        var files= pre_item.get('files');
        Util.forEach(files, function(f) {
            if (f.text('md5') === md5) {
                file= f;
                return false // break
            }
        })

        if (file) file.setExtendedDetails(
            data,
            function(items) {
                replaceItemsListEntry(uid, items)
                if (items.length === 0 || items[0].get('uid') !== uid || items.length > 1) $('#edit-item').dialog('close');
            }
        );
    };

    var createListEntry= function(item, empty) {
        var classes= ['itemlist-entry'];
        if (empty) classes.push('empty');
        var entry= new Util.Html('<div class="' + classes.join(' ') + '" uid="' + item.text('uid') + '" rating="' + item.text('rating') + '">', '</div>');
        if (!empty) entry.add(item.itemHtml());
        return entry.render();
    };

    // replaces item with old_id with given items, extends list as needed
    var replaceItemsListEntry= function(old_uid, items) {
        clearCache();
        var playlist= getCurrentPlaylist();
        if (!playlist) return;
        var $entry= $listSelector('.itemlist-entry[uid="' + old_uid + '"]');

        var new_items= [];
        var old_item= playlist.getItem(old_uid);
        var rem_items= [old_item];

        Util.forEach(items, function(item) {
            var uid= item.text('uid');

            // remove empty plays
            if (!item.get('files').length) {
                rem_items.push(item);
                return // continue
            }

            // if items contains old_uid, dont remove it later
            if (uid === old_uid) {
                rem_items.shift();
            }

            if ($entry.attr('uid') === uid) {
                Util.setHtml($entry, item.itemHtml());
            }
            else {
                $listSelector('.itemlist-entry[uid="' + uid + '"]').remove();
                $entry.after(createListEntry(item));
                $entry= $entry.next();
            }

            if (playlist.getItem(uid)) {
                // if item already in playlist, update item
                playlist.updateItem(item);
            }
            else {
                // if item NOT in playlist, add it later
                new_items.push(item);
            }
        })

        // add all new items
        if (new_items.length) playlist.addItems(new_items, undefined, old_item);

        // remove old items if it's NOT in item list
        if (rem_items.length) {
            Util.forEach(rem_items, function(item) {
                if (item) $listSelector('.itemlist-entry[uid="' + item.text('uid') + '"]').remove();
            });
            playlist.removeItems(rem_items);
        }

        Util.updateMarquees();
        selectEntries($listSelector('.itemlist-entry.selected'));
    }

    // builds details view of item (author, description, director etc.)
    // compares with optional reference data to show new/changed entires
    // used in diplaying hoerdat results and play info
    var buildItemDetails= function(data, ref_data) {
        var formatTitle= function(title) {return _title(title).bold()}
        var formatRoles= function(roles) {
            var role_table= (new Util.Html()).addTable(['striped']);
            Util.forEach(
                Util.filter(roles, function(dummy, role) {return role !== ''}).sort(),
                function(role) {role_table.addRow([role + ':', roles[role]])}
            )
            if (roles['']) {
                role_table.addRow(['Sonstige:', roles[''].sort().join(', ')]);
            }
            return role_table.render();
        };

        var table= (new Util.Html()).addTable(['striped']);
        // fields should be editable only if no hoerdat_id is set and no reference data was given (hoerdat results)
        var doEdit= !data.has('hoerdat_id') && !ref_data;

        var dimm= function(field, title, fn, dont_edit) {
            if (!data.has(field) && (!doEdit || dont_edit)) return;
            var text= fn ? fn(data.get(field)) : data.html(field);
            var classes= [];
            if (data.guessed(field)) {
                classes.push('guessed');
            }
            if (ref_data) {
                if (ref_data.has(field)) {
                    var ref_text= fn ? fn(ref_data.get(field)) : ref_data.html(field);
                    if (ref_text === text) {
                        classes.push('unchanged');
                    }
                    else {
                        classes.push('changed');
                    }
                }
                else {
                    classes.push('new');
                }
            }
            var td_class= (!dont_edit && doEdit) ? 'editable' : ''
            var class= '';
            if (classes.length) {
                class= ' class="' + classes.join(' ') + '"';
            }

            table.addRow([ title + ':', '<span field="' + field + '"' + class + '>' + text + '</span>' ], {'td': [ 'td-right', td_class ]});
        }

        dimm('title',        'Titel', formatTitle);
        dimm('hoerdat_id',   'H&ouml;rdat ID', null, 'dont_edit');
        dimm('other_titles', 'Alternative Titel');
        dimm('authornames',  'Autoren');
        dimm('directors',    'Regie');
        dimm('arrangers',    'Bearbeitung');
        dimm('rating',       'Bewertung');
        dimm('stations',     'Sender');
        dimm('genres',       'Genre');
        dimm('year',         'Erscheinungsjahr');
        dimm('description',  'Inhalt');
        dimm('roles',        'Mitwirkende', formatRoles, 'dont edit');
        return table.render();
    };

// ============================================================================
//      functions to view item's edit dialog
// ============================================================================

    // build items detail div containing tabbed item details
    var fillItemDetails= function(uid, detail_div) {
        Util.setHtml($(detail_div), '<div class="edit" uid="' + uid + '"></div>');
        var edit_div= $(detail_div).find('.edit')[0];
        $(edit_div).append('<ul></ul>');
        var edit_div_ul= $(edit_div).find('ul')[0];
        $(edit_div_ul).append('<li><a href="#detailEditInfo">Info</a></li>');
        $(edit_div_ul).append('<li><a href="#detailEditHoerdat">Hoerdat</a></li>');
        $(edit_div_ul).append('<li><a href="#detailEditFiles">Dateien</a></li>');
        $(edit_div).append('<div id="detailEditInfo"></div>');
        $(edit_div).append('<div id="detailEditHoerdat"><form></form><div class="result"></div></div>');
        $(edit_div).append('<div id="detailEditFiles"><div class="filelist"></div><div class="editfile"></div></div>');
        var search_form= $(edit_div).find('#detailEditHoerdat form')[0];
        var table= new Util.Html().addTable();
        table.addRow([
            '<label for="frm_search_title">Titel</label>:',
            '<input id="frm_search_title" type="text" size="50" name="title"/>',
        ]);
        table.addRow([
            '<label for="frm_search_author_given">Autor</label>:',
            '<input id="frm_search_author_given" type="text" name="author_given"/>' +
            '<input id="frm_search_author_name" type="text" name="author_name"/>' +
            ' <input type="submit" value="Los">',
        ]);
        table.render($(search_form));

        $(search_form).submit(function() { searchHoerdat(uid, search_form); return false; });

        $(edit_div).tabs({
            'select': function(event, ui) {
                // if hoerdat tab is selected and result is empty: start hoerdat search
                if (ui.index === 1) {
                    if (!$(search_form).next().children().length) {
                        $(search_form).submit();
                    }
                }
            },
        });

        getItem(uid).getDetails(function (item) {
            var $info_tab= $(edit_div).find('#detailEditInfo');
            var $search_tab= $(edit_div).find('#detailEditHoerdat');

            Util.setHtml(
                $info_tab,
                buildItemDetails(item) + '<div class="save hidden"><a href="' + Util.buildCmdRef('setdetails', {'uid': uid}) + '">&Auml;nderungen speichern</a></div>'
            );

            fillFileList(uid);

            var form_title= item.text('title');

            var author_name= '';
            var author_given= '';
            var authors= item.get('authors');
            if (authors && authors.length) {
                author_name= authors[0].name || '';
                author_given= authors[0].given_name || '';
            }

            $search_tab.find('input[name="title"]').val(form_title);
            $search_tab.find('input[name="author_given"]').val(author_given);
            $search_tab.find('input[name="author_name"]').val(author_name);
            $search_tab.find('.result').empty();

            // if title was guessed, jump to hoerdat search
            if (item.guessed('titles')) {
                $(edit_div).tabs('select', 1);
            }
        });
    };

    // fills file list in files view in item details
    var fillFileList= function(uid) {
        var item= getItem(uid);
        var files= item.get('files');
        var files_div= $('#detailEditFiles .filelist')[0];
        $(files_div).empty();
        $(files_div).append('<div class="save invisible"><a href="' + Util.buildCmdRef('savefilelist',   {'uid': uid}) + '">&Auml;nderungen speichern</a></div>');
        $(files_div).next().empty();

        Util.forEach(files, function(file, i) {
            var div= new Util.Html('<div class="file" md5="' + file.text('md5') + '" uid="' + uid + '">', '</div>');
            var addclass= i > 0 ? '' : ' invisible';
            div.add('<div class="move-up ui-icon ui-icon-arrow-1-n' + addclass + '">', '</div>');
            addclass= file.int('play_order') < 0 ? 'ui-icon-plus' : 'ui-icon-minus';
            div.add('<div class="toggle-play ui-icon ' + addclass + '">', '</div>');
            addclass= file.int('play_order') < 0 ? 'disabled' : '';
            var length= file.int('length');
            length= length ? ' ' + Util.formatTime(length) : '';
            div.add('<div class="' + addclass + '">', '</div>').add(
                '<a href="' + Util.buildCmdRef('editfile', {'md5': file.text('md5'), 'uid': uid}) + '">',
                '</a>' + length
            ).add(file.text('name'));
            $(files_div).append(div.render());
        })
    };

    var getItem= function(uid) {return getCurrentPlaylist().getItem(uid)}

    var getCurrentPlaylist= function() {return _playlists[_playlist_tab]}

    var updateDocumentTitle= function() {
        var playlist= getCurrentPlaylist();
        if (!playlist) {
            document.title= '(Keine Playlist ausgewählt)';
            return;
        }

        document.title= 'Playlist "' + playlist.text('name') + '"';
    };

    // selects given playlist
    var selectPlaylist= function(playlist) {
        var pl_select= $('#playlistselect')[0];
        if (typeof playlist === 'undefined') playlist= getCurrentPlaylist();
        if (!playlist) {
            pl_select.selectedIndex= -1;
            $(pl_select).change();
            return;
        }

        $(pl_select).val(playlist.text('playlist_id'));
        var curPlaylist= getCurrentPlaylist();
        if (!curPlaylist || curPlaylist.text('playlist_id') !== playlist.text('playlist_id')) {
            $(pl_select).change();
        }
    }

    var fillPlaylistSelect= function() {
        var $pl_select= $('#playlistselect');
        $pl_select.empty();
        var playlists= Playlist.getSortedPlaylists();
        Util.forEach(playlists, function(playlist) {
            var option= playlist.text('name');
            var descr= playlist.text('description');
//            if (descr) option+= '<span class="description">' + descr + '</span>';
            $pl_select.append('<option title="' + descr + '" value="' + playlist.text('playlist_id') + '" class="' + playlist.text('playlist_type') + '">' + option + '</option>');
        });

        selectPlaylist();
    }

    var getViewedPlays= function(fn_filter) {
        if (!fn_filter) fn_filter= function(obj) {return true};
        var plays= [];
        $listSelector('.itemlist .itemlist-entry').each(function() {
            // skip filtered entries
            if (!fn_filter(this)) return true;
            var play_uid= $(this).attr('uid');
            if (play_uid) {
                var play= getItem(play_uid);
                if (play) plays.push(play);
            }
            return true;
        });
        return plays;
    };

    var getCheckedPlays= function() {return getViewedPlays(
        function(obj) {return $(obj).hasClass('selected') && $(obj).css('display') !== 'none'}
    )};

    var updatePlaylistop= function() {
        var playlist= getCurrentPlaylist();
        $('#playlistop li').removeClass('ui-state-disabled');
        if (!playlist) $('#playlistop .pl-open').addClass('ui-state-disabled');
        if (!playlist || playlist.text('playlist_type') !== 'real') {
            $('#playlistop .pl-delete').addClass('ui-state-disabled');
            $('#playlistop .pl-rename').addClass('ui-state-disabled');
            $('#playlistop .pl-save').addClass('ui-state-disabled');
            $('#playlistop .pl-remove').addClass('ui-state-disabled');
        }
        if (_playlists.target) {
            $('#playlistop .pl-add').removeClass('ui-state-disabled');
        }
        else {
            $('#playlistop .pl-add').addClass('ui-state-disabled');
        }
    };

// ============================================================================
//      Live handlers
// ============================================================================

    var _init_live= function() {

        $('#pl-tabs span').live('click', function() {
            switch(this.id) {
                case 'pl-player': _playlist_tab= 'player'; break;
                case 'pl-target': _playlist_tab= 'target'; break;
                case 'pl-source': _playlist_tab= 'source'; break;
            }

            // $('html').removeClass('mode-player mode-target mode-source').addClass('mode-' + _playlist_tab);

            $('html').removeClass('dummy').addClass('dummy');


            $('html').attr('mode', _playlist_tab);
            updateDocumentTitle();
            clearCache();
            selectPlaylist();
            updatePlaylistop();
            onMainScroll.now();
        });

        // plays item on dblclick
        $('.itemlist .itemlist-entry').live('dblclick', function() {
            var uid= $(this).find('.iteminfo').attr('uid');
            Event.fire('playItem', uid, getCurrentPlaylist());
            return false;
        });

        // item checked (or unchecked)
        $('.itemlist .iteminfo .select').live('click', function() {
            if ($(this).attr('checked')) {
                selectEntries($(this).parents('.itemlist-entry'));
            }
            else {
                deselectEntries($(this).parents('.itemlist-entry'));
            }
        });

        // edit button pressed
        $('.itemlist .iteminfo .edit').live('click', function() {
            var uid= $(this).parents('.iteminfo').attr('uid');
            // div will bes shown. update contents
            var detail_div= $('#edit-itemdetails')[0];
            fillItemDetails(uid, detail_div);
            $('#edit-item').dialog('option', 'title', _title(getItem(uid).text('title'))).dialog('open');
            return false;
        });

        // handle clicks on icons in file list in items details
        $('#edit-itemdetails .filelist .file .ui-icon').live('click', function() {
            var $file_div= $(this).parents('.file');
            var md5= $file_div.attr('md5');
            var uid= $file_div.attr('uid');

            var files= getItem(uid).get('files');
            var this_file_index= -1;
            for (var i in files) {
                if (files[i].text('md5') === md5) {
                    this_file_index= i;
                    break;
                }
            }
            if (this_file_index < 0) return;
            if ($(this).hasClass('move-up')) {
                if (this_file_index > 0) {
                    var play_order_1= files[this_file_index - 1].int('play_order');
                    var play_order=   files[this_file_index].int('play_order');
                    var swap= files[this_file_index - 1];
                    files[this_file_index - 1]= files[this_file_index];
                    files[this_file_index]= swap;

                    files[this_file_index - 1].set('play_order', Math.abs(play_order_1) * (play_order   < 0 ? -1 : 1));
                    files[this_file_index    ].set('play_order', Math.abs(play_order  ) * (play_order_1 < 0 ? -1 : 1));
                }
            }
            if ($(this).hasClass('toggle-play')) {
                files[this_file_index].set('play_order', -files[this_file_index].int('play_order'));
            }
            var $filelist_div= $(this).parents('div.filelist');
            fillFileList(uid);
            $filelist_div.find('div.save').removeClass('invisible');
        });

        // make texts in edit dialog editable on dblclick
        $('#edit-itemdetails .edit td.editable').live('dblclick',
            function(event) {
                var $span= $(this).find('span');
                var uid= $(this).parents('.edit').attr('uid');
                var item= getItem(uid);
                var field= $span.attr('field');
                if (field === 'description') {
                    Util.setHtml($span, '<textarea cols="50" rows="6"></textarea>');
                }
                else {
                    Util.setHtml($span, '<input type="text" size="50"/>');
                }
                var $input= $span.children();
                var dialog= $('#edit-item')[0];
                // disable close on escape during edit
                $(dialog).dialog('option', 'closeOnEscape', false);
                $input.val(item.text(field));
                $input.focus();
                $input.blur(
                    function() {
                        item.set(field, $input.val());
                        // re-enable close on escape after edit
                        $(dialog).dialog('option', 'closeOnEscape', true);
                        $span.parents('table').replaceWith(buildItemDetails(item));
                        if (item.changed()) {
                            $('#detailEditInfo .save.hidden').removeClass('hidden');
                        }
                    }
                );
                $input.keypress(
                    function(e) {
                        if (e.keyCode === 13 && ($input.is('input') || e.ctrlKey)) {
                            $input.blur();
                            return false;
                        }
                        if (e.keyCode === 27) {
                            console.debug('escape')
                            $input.val(item.text(field));
                            $input.blur();
                            return false;
                        }
                    }
                );
            }
        );

        // hover handling for itemlist entries
        $('.itemlist .itemlist-entry')
            .live('mouseover', function(event) {
                $(this).addClass('hover')
                showItemTooltip.start(event);
            })
            .live('mousemove', function(event) {
                showItemTooltip.start(event);
            })
            .live('mouseout', function() {
                $(this).removeClass('hover')
                // hide tooltip
                showItemTooltip.stop();

                var iteminfo_div= $dialog_iteminfo.find('.iteminfo')[0];
                if ($dialog_iteminfo.dialog('isOpen') && $dialog_iteminfo.hasClass('sticky')) return;
                $dialog_iteminfo.dialog('close');
            })
            .live('click', function(event) {
                if (!$dialog_iteminfo.dialog('isOpen')) return;
                $dialog_iteminfo.toggleClass('sticky');
            });

        $('#dialog-iteminfo').live('click', function() {
            $(this).dialog('close');
        });

        $('#search').live('keypress', function(ev) {
            updateSearch.start(ev);
        });

        // manage playlist operation buttons
        $('#operation #playlistop li').live('click', function() {
            if ($(this).hasClass('ui-state-disabled')) return false;

            var dialog= $('#edit-playlist')[0];
            var playlist= getCurrentPlaylist();
            if (!playlist && !$(this).hasClass('pl-new')) return false;

            if ($(this).hasClass('pl-new') || $(this).hasClass('pl-rename')) {
                Util.setHtml($(dialog).find('.pl-edit'), '<form></form>');
                var form= $(dialog).find('form')[0];
                Util.setHtml($(form),'<input type="text" size="30" name="name"/>');

                var buttons= {
                    'Abbrechen': function() { $(dialog).dialog('close') },
                };
                var button_text;
                var title;
                var fn_submit;
                if ($(this).hasClass('pl-new')) {
                    title= 'Neue Playlist erstellen';
                    button_text= 'Erstellen';
                    fn_submit= function() {
                        Playlist.createPlaylist($(form).find('input[name="name"]').val());
                    };
                }
                else {
                    var pl_id= playlist.text('playlist_id');
                    var pl_name= playlist.text('name');
                    title= 'Playlist "' + pl_name + '" umbenennen';
                    button_text= 'Umbenennen';
                    fn_submit= function() {
                        Playlist.renamePlaylist(playlist, $(form).find('input[name="name"]').val());
                    };
                    $(form).find('input[name="name"]').val(pl_name);
                }

                buttons[button_text]= function() { $(form).submit() };
                $(dialog).dialog('option', 'buttons', buttons );
                $(dialog).dialog('option', 'title', title );
                $(form).submit(function() {
                    fn_submit();
                    $(dialog).dialog('close');
                    return false;
                });
                $(dialog).dialog('open');
            }

            if ($(this).hasClass('pl-open')) {
                $('#playlistselect').change();
            }
            if ($(this).hasClass('pl-save')) {
                playlist.saveOrder(Util.map(getViewedPlays(), function(play) {return play.text('play_id')}));
            }
            if ($(this).hasClass('pl-delete')) {
                $(dialog).find('.pl-edit').empty();
                $(dialog).dialog('option', 'buttons', {
                    'Abbrechen': function() { $(dialog).dialog('close') },
                    'Entfernen': function() {
                        for (var tab in _playlists) {
                            if (_playlists[tab] && _playlists[tab].text('uid') === playlist.text('uid')) {
                                setPlaylist(tab, null);
                            }
                        }
                        Playlist.deletePlaylist(playlist);
                        $(dialog).dialog('close');
                    }
                });
                $(dialog).dialog('option', 'title', 'Playlist "' + playlist.text('name') + '" wirklich l&ouml;schen?');
                $(dialog).dialog('open');
            }

            if ($(this).hasClass('pl-add') || $(this).hasClass('pl-remove')) {
                var plays= getCheckedPlays();
                if (!plays.length) return false;

                if ($(this).hasClass('pl-add')) {
                    if (!_playlists.target) return true;
                    Playlist.addToPlaylist(_playlists.target, plays);
                }
                else {
                    Playlist.removeFromPlaylist(playlist, plays);
                }
            }
            return false;
        });
    };

    var _init= function() {
        _init_live();

        // create rating filter
        $('#ratingfilter').slider({
            min: -1,
            max: 10,
            value: 0,
            slide: function(event, ui) {
                clearCache();
                var $body= $('#body');
                var attr= [];
                if (ui.value === -1) {
                    attr= []
                    for (var i= 1; i < 11; i++) attr.push('no_rating_' + i)
                }
                else if (ui.value > 0) {
                    attr= []
                    for (var i= 1; i < ui.value; i++) attr.push('no_rating_' + i)
                }
                $body.attr('filter', attr.join(' '));
                onMainScroll.now();
            },
        });

        $('#search').val('');
        $('#searchform').submit(function(ev) {
            updateSearch.stop();
            selectPlaylist(Playlist.getPlaylist('search:' + $('#search').val(), 'create if not exists'));
            return false;
        });
        $('#selection-op span').click(function() {
            var sort_order= null;
            if ($(this).hasClass('sort-abc')) {
                sort_order= 'abc';
            }
            if ($(this).hasClass('sort-orig')) {
                sort_order= 'orig';
            }
            if ($(this).hasClass('sort-cba')) {
                sort_order= 'cba';
            }
            if ($(this).hasClass('sort-scramble')) {
                sort_order= 'random';
            }
            if (sort_order) {
                _playlist_order[_playlist_tab]= sort_order;
                viewItemlist();
            }

            if ($(this).hasClass('select-all')) {
                selectEntries($listSelector('.itemlist .itemlist-entry'));
            }
            else if ($(this).hasClass('select-none')) {
                deselectEntries($listSelector('.itemlist .itemlist-entry'));
            }
            else if ($(this).hasClass('select-invert')) {
                // select all and deselect previously selected
                var $old_sel= $listSelector('.itemlist .itemlist-entry.selected');
                selectEntries($listSelector('.itemlist .itemlist-entry'));
                deselectEntries($old_sel);
            }
        });

        $('#playlistselect').change(function() {
            var playlist= Playlist.getPlaylist($(this).val());
            if (!playlist) return;
            loadViewPlaylist(playlist);
            if (_playlist_tab === 'source') Util.doJsonRequest('set-lastplaylist', { playlist_id: playlist.text('playlist_id') });
            updatePlaylistop();
        });

        Event.add('playlistListChanged', fillPlaylistSelect);
        Event.add('playlistCreated', function(playlist) {
            if (_playlist_tab === 'target') {
                selectPlaylist(playlist);
            }
            else {
                loadViewPlaylist(playlist, 'target');
            }
        });
        Event.add('activeItemChanged', highlightActiveEntry);
        Event.add('updatedListItem', function() {
            Event.fire('activeItemChanged', true);
            updateSelectedEntries();
        });
        Event.add('selectPlaylist', selectPlaylist);
        Event.add('updatedPlaylist', function(playlist) {
            for (var tab in _playlists) {
                if (_playlists[tab] === playlist) {
                    viewItemlist(tab);
                }
            }
        });
        Event.add('changedPlayersPlaylist', function(playlist) {
            loadViewPlaylist(playlist, 'player');
            if (_playlist_tab === 'player') selectPlaylist();
        });
        Event.add('changedPlayersOrder', function(order) {
            _playlist_order.player= order;
            viewItemlist('player');
        });

        Event.add('setRating', function(uid, rating) {
            var item= getItem(uid);
            if (item && item.setRating) {
                item.setRating(rating);
            }
            return false;
        });
    };

    var initWui= function(last_playlists, fn) {
        Playlist.getPlaylists(function() {
            fillPlaylistSelect();
            for (tab in _playlists) {
                var playlist= null
                if (last_playlists[tab]) {
                    playlist= Playlist.getPlaylist(last_playlists[tab], 'create if not exists')
                }
                loadViewPlaylist(playlist, tab);
            }
            selectPlaylist();
            fn();
        });
    };

// ============================================================================
//      Init and Exports
// ============================================================================

    _init();

    return {
        getCurrentPlaylist: getCurrentPlaylist,
        loadViewPlaylist: loadViewPlaylist,
        saveFilelist: saveFilelist,
        setDetails: setDetails,
        editFile: editFile,
        initWui: initWui,
    };


// ============================================================================
//      Prologue
// ============================================================================

    })();

});

