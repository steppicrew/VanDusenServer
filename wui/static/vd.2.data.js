
// ============================================================================
//      Data Class
// ============================================================================

jQuery(function($, undefined) {

// ============================================================================
//      Import Modules
// ============================================================================

    var Util= VD.Util;
    var Event= VD.Event;

// ============================================================================
//      Data Class Implementation
// ============================================================================

    var DATA_FIELDMAP= {
        'title':        'titles',
        'other_titles': 'titles',
        'authornames':  'authors',
        'play_files':   'files',
    };

    var _ItemBase= function(data, fn_data) {
        if (!data) data= {};
        if (!fn_data) fn_data= {};

        var changed= false;

        var _guessed= data['.guessed'] || {};
        delete data['.guessed'];

        var _is_minimized= data['.minimized'];
        delete data['.minimized'];

        var _invalid_details= false;

        fn_data.uid= (function() {
            var _uid= null;
            return function() {
                if (!_uid) {
                    var id_name= text('id_name');
                    _uid= id_name + ':' + encodeURIComponent(text(id_name));
                }
                return _uid;
            };
        })();

        // get playable files
        fn_data.play_files= function() {
            return Util.filter(get('files'), function(file) {return file.int('play_order') >= 0})
        }

        // build authornames
        fn_data.authornames= function() {
            return Util.map(
                get('authors') || [],
                function(author) {
                    return Util.filter(
                        Util.map(
                            [ 'given_name', 'name' ],
                            function(part) {return author[part]}
                        ),
                        function(part) {return part}
                    ).join(' ')
                }
            )
        }

        // separate main title from other titles
        fn_data.title= function() {
            var titles= get('titles') || [];
            if (titles.length) return titles[0];
            return null;
        };

        fn_data.other_titles= function() {
            var titles= get('titles') || [];
            if (titles.length) return titles.slice(1);
            return null;
        };

        if (!fn_data.sort_text) fn_data.sort_text= function() {return ''}
        if (!fn_data.files)     fn_data.files=     function() {return []}
        if (!fn_data.id_name)   fn_data.id_name=   function() {return '**unknown**'}

        var fieldMap= function(field) {
            return DATA_FIELDMAP[field] || field;
        };

        // returns true if data or guessed contains field
        var has= function(field) {
            field= fieldMap(field);
            if (data[field]     != null) return true;
            if (_guessed[field] != null) return true;
            return false;
        };

        // returns true if data is only guessed
        var guessed= function(field) {
            field= fieldMap(field);
            return data[field] == null;
        };

        // returns actual value
        var get= function(field) {
            if (fn_data[field]) return fn_data[field]();

            var value= data[field];
            return value == null ? _guessed[field] : value;
        };

        // returns value as text
        var _text= function(value) {
            switch (typeof value) {
                case 'string':   return value;
                case 'number':   return '' + value;
                case 'function': return _text(value());
                case 'object':
                    if (value) {
                        if ($.isArray(value)) {
                            return Util.map(value, function(v) {return _text(v)}).sort().join(', ');
                        }

                        var s= []
                        Util.forEach(value, function(v, i) {s.push(_text(i) + ': ' + _text(v))})
                        s.sort();
                        if (s.length) return '[' + s.join(', ') + ']';
                    }
                    break;
            }
            return '';
        };

        // returns field's value as text
        var text= function(field) {
            return _text(get(field));
        };

        // returns field as html
        var html= function(field) {
            return text(field).replace(/\n/g, '<br/>')
        };

        // returns field as integer
        var int= function(field) {
            var value= text(field)
            if (value) return parseInt(value, 10);
            return null;
        };

        // adds current data's id to given params
        var addIdParams= function(params) {
            if (!params) params= {};
            params.type= data.type;
            var id_name= text('id_name');
            params[id_name]= text(id_name);
            return params;
        };

        var getDetails= function(fn) {
            if (!_invalid_details && !_is_minimized) {
                if (fn) fn(this);
                return;
            }
            Util.doJsonRequest('getdetails',
                addIdParams(),
                function(json) {
                    var item= VD.Item.create(json);
                    Event.fire('updatedItem', item);
                    return item;
                },
                fn
            );
        };

        var setDetails= function(new_data, fn) {
            Util.doJsonRequest('setdetails',
                addIdParams({ 'data': new_data || data, }),
                function(json) {
                    var item= VD.Item.create(json);
                    Event.fire('updatedItem', item);
                    return item;
                },
                fn
            );
        };

        var invalidateDetails= function() {
            _invalid_details= true;
        };

        // sets field with text value, converts as needed
        var set= function(field, value) {
            if (typeof value === 'string') {
                value= Util.trim(value).replace(/\s*\n\s*/g, "\n").replace(/\s\s+/g, ' ');
            }

            var _parseArray= function(text) {
                if (!text) return null;
                var array= Util.filter(Util.map(text.split(','), function(value) {return Util.trim(value)}), function(value) {return value});
                if (array.length) return array;
                return null;
            };

            switch (field) {
                case 'authornames':
                    value= _parseArray(value);
                    if (value) {
                        value= Util.map(value, function(a_name) {
                            var author_parts= a_name.split(' ');
                            var name= author_parts.pop();
                            return { 'name': name, 'given_name': author_parts.join(' ') || null };
                        })
                    }
                    field= 'authors';
                    break;

                case 'directors':
                case 'arrangers':
                case 'genres':
                case 'keywords':
                case 'stations':
                    value= _parseArray(value);
                    break;

                case 'title':
                    if (value) {
                        var title= value;
                        value= (get('titles') ||[]).slice(1);
                        value.unshift(title);
                    }
                    else {
                        value= null;
                    }
                    field= 'titles';
                    break;

                case 'other_titles':
                    var value= _parseArray(value);
                    var title= get('title');
                    if (title) {
                        if (!value) value= [];
                        value.unshift(title);
                    }
                    field= 'titles';
                    break;

                case 'quality':
                case 'hoerdat_id':
                case 'last_played':
                case 'play_order':
                case 'year':
                case 'rating':
                    if (value) {
                        value= parseInt(value, 10);
                        if (isNaN(value)) value= null;
                    }
                    break;
            }

            switch (typeof value) {
                case 'string':
                    if (value === '') value= null;
                    break;
                case 'object':
                    if (value && value.length === 0) value= null;
            }
            if (field && _text(data[field]) !== _text(value)) {
                changed= true;
                data[field]= value;
            }
        };

        // builds playlist entry or players display
        var itemHtml= function() {
            var uid= text('uid');
            var content= new Util.Html('<div class="iteminfo" uid="' + uid + '">', '</div>');

            var left_ui= content.add('<div class="ui-left ui-widget">', '</div>');
            var add_class= text('type') === 'play' ? '' : ' invisible';
//            left_ui.add('<input type="checkbox" class="select' + add_class + '"/>');
            left_ui.add('<input type="checkbox" class="select"/>');

            var main_title= text('title');
            if (!main_title && data.type) main_title= '(unbenannt)';
            add_class= (main_title && guessed('title')) ? ' guessed' : '';
            var main_div= content.add('<div class="iteminfo-main">', '</div>');
            var title_div= main_div.add('<div class="title">', '</div>');
            var rate_div= title_div.add('<div class="rating rating-value' + get('rating') + '">', '</div>');
            var maintitle_div= title_div.add('<div class="maintitle' + add_class + ' marquee">', '</div>');
            maintitle_div.add(main_title);
            var part_num= get('part_num');
            var part_count= get('part_count');
            if (part_num && part_count) {
                add_class= guessed('part_num') ? ' guessed' : '';
                maintitle_div.add('<span class="subtext part' + add_class + '">', '</span>').add('Teil ' + part_num + ' von ' + part_count);
            }
            var addition= get('addition');
            if (addition) {
                add_class= guessed('addition') ? ' guessed' : '';
                maintitle_div.add('<span class="subtext addition' + add_class + '">', '</span>').add('(' + addition + ')');
            }

            if (has('rating')) {
                var a= new Util.Html();
                var rating= int('rating')
                for (var s= 5; s > 0; s--) {
                    var new_a= new Util.Html('<span class="star' + s + '">', '</span>');
                    var half= 2*s === rating ? 1 : 0;
                    if (s === 1 && rating === 1) half= 2;
                    new_a.add('<a href="' + Util.buildCmdRef('setrating', {'uid': uid, 'rating': 2*s - half}) + '">', '</a>')
                        .add('<img src="/static/star-dummy.png">');
                    new_a.addItem(a);
                    a= new_a;
                }
                rate_div.addItem(a);
            }
            var subtitle_div= main_div.add('<div class="subtitle">', '</div>');
            var bottom_ui= subtitle_div.add('<div class="subtext ui-bottom ui-widget">', '</div>');
            bottom_ui.add('<a class="ui-icon ui-icon-pencil edit">', '</a>');

            var time_sec= get('last_played');
            var timeinfo= 'Noch nie gespielt';
            add_class= ' ui-state-disabled';
            if (time_sec) {
                // seconds to milliseconds
                var date= new Date(time_sec * 1000);
                var to2= function(i) { i = '' + i; while (i.length < 2) i= '0' + i; return i; };
                var to4= function(i) { i = '' + i; while (i.length < 4) i= '0' + i; return i; };
                var date_str= to2(date.getDate()) + '.' + to2(date.getMonth() + 1) + '.' + to4(date.getFullYear()) + ' ' + to2(date.getHours()) + ':' + to2(date.getMinutes()) + ':' + to2(date.getSeconds());
                timeinfo= 'Zuletzt gespielt: ' + date_str;
                add_class= ''
            }
            bottom_ui.add('<a class="ui-icon ui-icon-clock' + add_class + '" title="' + timeinfo + '">', '</a>');
            var timeinfo= subtitle_div.add('<div class="timeinfo subtext">', '</div>');
            timeinfo.add('<span class="positioninfo" title="aktuelle Position">', '</span>').add('<span class="text">+</span><span class="position">', '</span>').add(Util.formatTime(0));
            var time_length= int('length');
            time_length= time_length ? Util.formatTime(time_length) : '(unbekannt)';
            timeinfo.add('<span class="lengthinfo" title="Gesamtl&auml;nge">', '</span>').add('<span class="text"></span><span class="length">', '</span>').add(time_length);
            timeinfo.add('<span class="remaininfo" title="Verbleibend">', '</span>').add('<span class="text">-</span><span class="remain">', '</span>').add(time_length);

            var subtext_div= subtitle_div.add('<div class="marquee">', '</div>');
            var subtexts= [];
            var addSubText= function(field, str) {
                if (str || has(field)) {
                    var classes= [ 'subtext', field, ];
                    if (!str && guessed(field)) classes.push('guessed');
                    var subtext= new Util.Html('<span class="' + classes.join(' ') + '">', '</span>');
                    subtext.add(str || text(field));
                    subtexts.push(subtext.render());
                }
            };

            var search_score= get('search_score');
            if (search_score) {
                search_score= parseFloat(search_score);
                if (! isNaN(search_score)) {
                    var search_score_int= Math.floor(search_score);
                    var search_score_frac= ((search_score - search_score_int) + '0000').slice(2, 4);
                    addSubText('search-score', search_score_int + '.' + search_score_frac);
                }
            }
            addSubText('authornames');
            addSubText('genres');
            addSubText('stations');

            var files= get('files');
            var play_files= get('play_files');
            if (files.length > 1 || files.length !== play_files.length) {
                addSubText('file-count', play_files.length + '/' + files.length);
            }
            subtext_div.add(subtexts.join('<span class="subtext spacing">-</span>'));
            if (play_files.length > 1) {
                subtext_div.add('<span class="subtext file-no">', '</span>');
            }

            return content.render()
        }

        var sortKey= function(markChanged) {
            var result= {
                uid:        text('uid'),
                sort_text:  text('sort_text'),
                sort_pos:   int('sort_pos'),
                random_pos: text('random_pos'),
            }
            if (markChanged) result.changed= !result.sort_pos || !result.random_pos

            if (!result.random_pos) result.random_pos= '' + Math.random()

            return result
        }

        this.type=      data.type
        this.rawData=   function() {return data}
        this.has=       has
        this.guessed=   guessed
        this.get=       get
        this.text=      text
        this.html=      html
        this.int=       int
        this.addIdParams= addIdParams
        this.changed=   function() {return changed}
        this.getDetails= getDetails
        this.setDetails= setDetails
        this.invalidateDetails= invalidateDetails
        this.set=       set
        this.itemHtml=  itemHtml
        this.sortKey=   sortKey

        return this
    }

// ============================================================================
//      _Play Class Implementation
// ============================================================================

    var _Play= function(data) {
        if (data.type !== 'play') {
            console.error('Data is not of type "play"');
            return {};
        }

        // create guessed data if not already done
        if (!data['.guessed']) data['.guessed']= {};

        var getFiles= (function() {
            var files= data.files || [];
            delete data.files;

            // convert files to object
            files= Util.map(files, function(f) {
                var file= new _File(f);

                // get some guessed data from files
                Util.forEach(
                    Util.filter(
                        ['authors', 'titles', 'stations', 'year'],
                        function(field) {return data['.guessed'][field] === undefined}
                    ),
                    function(field) {
                        data['.guessed'][field]= file.get(field);
                    }
                );
                return file;
            });

            // sort files
            files= Util.stringSorter(files, function(a) {return a.get('sort_text')})

            // build play order
            Util.forEach(files, function(file, i) {
                var play_order= file.int('play_order');
                var new_play_order= parseInt(i, 10) + 1;
                if (play_order < 0) new_play_order= -new_play_order;
                if (play_order !== new_play_order) file.set('play_order', new_play_order);
            })
            return function() {return files}
        })();

        var me= this;

        _ItemBase.call(this, data, {
            'files': getFiles,
            'last_played': function() {
                var result= 0;
                var files= getFiles();
                Util.forEach(files, function(file) {
                    var last_played= file.int('last_played');
                    if (last_played > result) result= last_played;
                });
                return result;
            },
            'length': function() {
                var result= 0;
                var files= me.get('play_files');
                Util.forEach(files, function(file) {result += file.int('length')});
                return result;
            },
            'sort_text': function() {return me.text('title')},
            'id_name': function() {return 'play_id'},
        });

        var setRating= function(rating, fn) {
            if (rating === this.int('rating')) return;
            Util.doJsonRequest('setrating',
                this.addIdParams({
                    'rating': rating,
                }),
                function(json) {
                    var item= VD.Item.create(json);
                    Event.fire('updatedItem', item);
                    return item;
                },
                fn
            );
        };

        var setFilesOrder= function(order, fn) {
            Util.doJsonRequest('setplaysfileorder',
                this.addIdParams({
                    'order': order,
                }),
                function(json) {
                    var item= VD.Item.create(json);
                    Event.fire('updatedItem', item);
                    return item;
                },
                fn
            );
        };

        this.setRating= setRating;
        this.setFilesOrder= setFilesOrder;

        return this;
    };

// ============================================================================
//      _File Class Implementation
// ============================================================================

    var _File= function(data) {
        if (data.type !== 'file') {
            console.error('Data is not of type "file"');
            return {};
        }
        var _guessed_titles= (data['.guessed'] || {}).titles;

        var me= this;

        _ItemBase.call(this, data, {
            'titles': function() {
                if (me.has('titles')) return data.titles || _guessed_titles;
                var name= me.text('name');
                if (name) name= name.replace(/\.mp.$/i, '')
                return [name];
            },
            'sort_text': function() {
                var play_order= me.int('play_order') || 9999;
                return [ Math.abs(play_order), play_order, me.text('part_num'), me.text('part_count'), me.text('title'), me.text('name') ].join('~');
            },
            'files':   function() {return [ me ]},
            'url':     function() {return '/' + encodeURIComponent(me.get('dir') + '/' + me.get('name'))},
            'id_name': function() {return 'md5'},
        });

        var setExtendedDetails= function(details, fn) {
            Util.doJsonRequest('setextendedfiledetails',
                this.addIdParams({
                    'data': details,
                }),
                function(json) {
                    return Util.map(json.items, function(i) {
                        var item= VD.Item.create(i);
                        Event.fire('updatedItem', item);
                        return item;
                    })
                },
                fn
            );
        };

        var updateLastPlayed= function(fn) {
            Util.doJsonRequest(
                'set-file-lastplayed',
                {
                    'md5': me.text('md5'),
                },
                null,
                fn
            );
        };

        this.setExtendedDetails= setExtendedDetails;
        this.updateLastPlayed= updateLastPlayed;

        return this;
    };

// ============================================================================
//      _Playlist Class Implementation
// ============================================================================

    var _Playlist= function(data) {
        if (data.type !== 'playlist') {
            console.error('Data is not of type "playlist"');
            return {};
        }

        var me= this;
        var items_valid= false;

        _ItemBase.call(this, data, {
            'sort_text':     function() {return me.text('name')},
            'files':         function() {return []},
            'playlist_type': (function() {
                var playlist_type= null;
                return function() {
                    if (!playlist_type) playlist_type= me.text('playlist_id').split(':', 2)[0];
                    return playlist_type;
                };
            })(),
            'id_name':       function() {return 'playlist_id'},
        });

        var playlist_id= this.text('playlist_id');

        var items= {};
        var sorted_items= {};
        var items_sort_keys= [];
        var sorted_keys= {};

        var _resetSortCaches= function() {
            sorted_items= {};
            sorted_keys= {};
        };

        var sort= function(order) {
            if (!order) return;

            if (sorted_keys[order]) return sorted_keys[order];

            var fn_sortText;
            var inverse = false;
            switch (order) {
                case 'abc':
                case 'cba':
                    fn_sortText= function(a) {return a.sort_text}
                    inverse= order === 'cba';
                    break;

                default:
                    console.error('Sort order "' + order + '" is not allowed');
                case 'orig':
                    fn_sortText= function(a) {return a.sort_pos}
                    break;

                case 'random':
                    fn_sortText= function(a) {return a.random_pos}
                    break;
            }
            return sorted_keys[order]= Util.stringSorter(items_sort_keys, fn_sortText, inverse);
        };

        var getSortedItems= function(order) {
            if (sorted_items[order]) return sorted_items[order];

            return sorted_items[order]= Util.map(sort(order), function(key) {return items[key.uid]});
        };

        var savePlaysOrder= function() {
            if (me.get('playlist_type') !== 'real') return
            var data= {}
            var sort_keys= sort('orig')
            Util.forEach(sort_keys, function(key, i) {
                var item= items[key.uid];
                var sort_pos= parseInt(i, 10) + 1;
                sort_keys[i].sort_pos= sort_pos;
                data[item.text('play_id')]= {
                    sort_pos:   sort_pos,
                    random_pos: key.random_pos,
                }
            })
            console.debug('Saving plays order');
            Util.doJsonRequest('save-playlist-order',
                me.addIdParams({
                    'order': data,
                }),
                null,
                function(data) {
                    if (data.error) {
                        console.error(data.error);
                    }
                }
            )
        }

        // build sortable array containing various sort values and uid
        var buildItemsSort= function(unsorted_offset) {
            if (unsorted_offset === undefined) unsorted_offset= 100000
            _resetSortCaches();
            var changed= false;
            items_sort_keys= []
            Util.forEach(items, function(item) {
                var sort_key= item.sortKey(true)
                if (sort_key.changed) {
                    if (!sort_key.sort_pos) {
                        // append unsorted items to the end in the current order
                        sort_key.sort_pos= unsorted_offset + items_sort_keys.length
                    }
                    changed= true;
                    delete sort_key.changed;
                }
                items_sort_keys.push(sort_key);
            })
            if (changed) savePlaysOrder();
        };

        // returns index in ordered list
        var getItemIndex= function(uid, order) {
            var sorted= sort(order);
            var result= Util.forEach(sorted, function(v, i) {
                if (v.uid === uid) {
                    return parseInt(i, 10);
                }
            })
            if (result === undefined) return null
            return result
        };

        var getUidByIndex= function(index, order) {
            var sorted= sort(order);
            if (sorted[index]) return sorted[index].uid;
            return null;
        };

        var clear= function() {
            items= {};
            items_valid= false;
        };

        // receives full playlist, handles mutliple calls
        var load= function(fn) {
            if (items_valid) {
                if (fn) fn(items);
                return;
            }
            Util.doJsonRequest( 'getplaylist',
                {
                    'playlist_id': playlist_id,
                },
                function (js_data) {
                    items= {};
                    Util.forEach(
                        Util.map(
                            js_data.items,
                            function(i) {return VD.Item.create(i)}
                        ),
                        function(item) {items[item.text('uid')]= item}
                    )
                    items_valid= true;
                    buildItemsSort(js_data.items.length + 100000);
                    return items;
                },
                fn
            );
        };

        // build and save new random keys for playlist
        var scramble= function() {
            Util.forEach(items_sort_keys, function(key) {key.random_pos= Math.random()});
            _resetSortCaches();
            savePlaysOrder();
            Event.fire('updatedPlaylist', me);
        };

        var saveOrder= function(play_ids) {
            var play_id_map= {};
            _resetSortCaches();

            Util.forEach(play_ids, function(id, i) {
                play_id_map[id]= i;
            });

            Util.forEach(Util.filter(items_sort_keys, function(key) {return items[key]}), function(key) {
                key.sort_pos= play_id_map[items.text('play_id')];
            });

            savePlaysOrder();
        };

        var updateItem= function(item) {
            var uid= item.text('uid');
            if (items[uid]) items[uid]= item;
        };

        var rename= function(newname, fn) {
            if (me.get('playlist_type') !== 'real') return;
            Util.doJsonRequest('rename-playlist',
                me.addIdParams({
                    'newname': newname,
                }),
                null,
                function(data) {
                    if (data.ok) {
                        me.set('name', newname);
                        if (fn) fn();
                        return;
                    }
                    if (data.error) {
                        console.error(data.error);
                    }
                }
            );
        };

        var deletePl= function(fn) {
            if (me.get('playlist_type') !== 'real') return;
            Util.doJsonRequest('delete-playlist',
                me.addIdParams(),
                null,
                function(data) {
                    if (data.ok) {
                        if (fn) fn();
                        return;
                    }
                    if (data.error) {
                        console.error(data.error);
                    }
                }
            );
        };

        var addItems= function(add_items, fn, insert_after_item) {
            var sort_pos_prefix= 'XX';
            if (insert_after_item) {
                var uid= insert_after_item.get('uid');
                Util.forEach(items_sort_keys, function(sort_key) {
                    if (sort_key.uid === uid) {
                        sort_pos_prefix= sort_key.sort_pos;
                    }
                });
            }
            var sort_pos= 0;
            var new_items= add_items.concat();
            var play_ids= Util.map(
                Util.filter(
                    add_items,
                    function(item) {return item.get('type') === 'play'}
                ),
                function(item) {return item.get('play_id')}
            )

            var _finish= function() {
                Util.forEach(new_items, function(item) {
                    items[item.text('uid')]= item;
                    var sort_key= item.sortKey();
                    sort_key.sort_pos= sort_pos_prefix + '_' + (sort_pos++);
                    items_sort_keys.push(sort_key);
                });
                _resetSortCaches();
                savePlaysOrder();
                Event.fire('updatedPlaylist', me);
                if (fn) fn;
                return;
            };

            if (me.get('playlist_type') !== 'real') return _finish();
            Util.doJsonRequest('add-to-playlist',
                me.addIdParams({
                    'plays': play_ids,
                }),
                null,
                function(data) {
                    if (data.ok) {
                        return _finish();
                    }
                    if (data.error) {
                        console.error(data.error);
                    }
                }
            );
        };

        var removeItems= function(rem_items, fn) {
            var rem_plays= Util.filter(rem_items, function(item) {return items[item.text('uid')]})
            var play_ids= Util.map(
                Util.filter(
                    rem_plays,
                    function(item) {return item.get('type') === 'play'}
                ),
                function(item) {return item.get('play_id')}
            )

            var _finish= function() {
                Util.forEach(rem_plays, function(item) {delete items[item.text('uid')]});

                items_sort_keys= Util.filter(items_sort_keys, function(key) {return items[key.uid]});

                _resetSortCaches();
                Event.fire('updatedPlaylist', me);
                if (fn) fn;
                return;
            };

            if (!rem_plays.length) return;

            if (me.get('playlist_type') !== 'real') return _finish();

            Util.doJsonRequest('remove-from-playlist',
                me.addIdParams({
                    'plays': play_ids,
                }),
                null,
                function(data) {
                    if (data.ok) {
                        return _finish();
                    }
                    if (data.error) {
                        console.error(data.error);
                    }
                }
            );
        };

        this.clear= clear;
        this.load= load;
        this.scramble= scramble;
        this.updateItem= updateItem;
        this.rename= rename;
        this.destroy= deletePl;
        this.addItems= addItems;
        this.removeItems= removeItems;
        this.getItem= function(uid) {return items[uid]}
        this.items= function() {return items}
        this.sortedItems= getSortedItems;
        this.getItemIndex= getItemIndex;
        this.getUidByIndex= getUidByIndex;
        this.saveOrder= saveOrder;

        return this;
    };

    // creates playlist on server and calls callback on success
    var _PlaylistCreate= function(name, fn) {
        Util.doJsonRequest('create-playlist',
            {
                'name': name,
            },
            null,
            function(data) {
                if (data.ok) {
                    if (fn) fn(new _Playlist(data.playlist));
                    return;
                }
                if (data.error) {
                    console.error(data.error);
                }
            }
        );
    };

    VD.Item= {
        create: function(data){
            if (data && data.type) {
                switch (data.type) {
                    case 'play':     return new _Play(data)
                    case 'file':     return new _File(data)
                    case 'playlist': return new _Playlist(data)
                }
            }
            return new _ItemBase()
        },
        createPlaylist: _PlaylistCreate,
    }

});
