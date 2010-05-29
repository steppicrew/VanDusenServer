
// ============================================================================
//      Utility Library
// ============================================================================

jQuery(function($) {

    if (typeof VD === 'undefined') VD= {};

    var Event= VD.Event= (function() {
        var fns= {};

        var add= function(name, fn) {
            if (!fns[name]) fns[name]= [];
            fns[name].push(fn);
        };

        var fire= function() {
            var args= Array.prototype.slice.call(arguments);
            var name= args.shift();
// console.info('raised event ', arguments);
// console.trace();
            if (!fns[name]) {
                return;
            }
            VD.Util.forEach(fns[name], function(fn) {fn.apply(null, args)});
            return true;
        };
        return {
            add: add,
            fire: fire,
        };
    })();

    VD.Util= (function() {

// ============================================================================
//      Basic utility functions
// ============================================================================

    var strcmp= function(a, b) {
        if (a < b) return -1;
        if (a > b) return 1;
        return 0;
    };

    var trim= function(s) {
        if (typeof s !== 'string') return s;
        return s.replace(/^\s+/, '').replace(/\s+$/, '');
    }

    var stringSorter= function(a, fn_sortString, b_inverse) {
        var fn_sort= b_inverse
            ? function (a, b) {return strcmp(b[0], a[0])}
            : function (a, b) {return strcmp(a[0], b[0])}

        // idee: array aus [sorttext, original], nach [0] sortieren und array aus [1] zurueck
        // Fuehrende Leer- & Anfuehrungszeichen ignorieren
        return map(
            map(
                a,
                function(value) {
                    return [
                        ('' + fn_sortString(value)).toLowerCase().replace(/^[\s\"]+/, '')               // fix syntax highlighting: "
                        .replace(/(\d+)/g, function(str) {return 1000000000 + parseInt(str, 10)}),
                        value,
                    ]
                }
            ).sort(fn_sort),
            function(value) {return value[1]}
        )
    }

    var formatTime= function(iSec) {
        iSec= parseInt(iSec, 10);
        var sec= iSec % 60;
        if (sec < 10) sec= '0' + sec;
        var iMin= parseInt(iSec / 60, 10);
        if (iMin >= 60) {
            var min= iMin % 60;
            var h= parseInt(iMin / 60, 10);
            if (min < 10) min= '0' + min;
            return h + ':' + min + ':' + sec;
        }
        return iMin + ':' + sec;
    };

    var forEach= (function () {
        // define a unique value to be returned, if loop should be ended but forEach should return undefined
        var undef= {}
        return function(array, fn) {
            for (var i in array) {
                var result= fn(array[i], i, array, undef)
                if (result !== undefined) return result === undef ? undefined : result
            }
        }
    })()

    var map= function(array, fn) {
        var result= []
        for (var i in array) result.push(fn(array[i], i, array))
        return result
    }

    var filter= function(array, fn) {
        var result= []
        for (var i in array) if (fn(array[i], i, array)) result.push(array[i])
        return result
    }
// ============================================================================
//      TBD
// ============================================================================

    // merges content of src to dst
    var mergeData= function(src, dst) {
        forEach(src, function(v, i) {
            if (typeof v === 'object') {
                if (typeof dst[i] !== 'object') {
                    if (v == null) {
                        dst[i]= null;
                        return // continue
                    }
                    if ($.isArray(v)) {
                        dst[i]= [];
                    }
                    else {
                        dst[i]= {};
                    }
                }
                mergeData(v, dst[i]);
                return // continue
            }
            dst[i]= v;
        })
    };

    // returns a clone of src as object
    var cloneData= function(src) {
        var dst= {};
        mergeData(src, dst);
        return dst;
    }


// ============================================================================
//      Build JSON cmd request and run function on response
// ============================================================================

    // this version makes sure there is only one post running at a time
    var _singleInstancePost= (function() {
        var posts_data= {};
        var post_queue= [];

        var log= false // || true

        // set this to true if only one request should be running at a time
        var singleCmd= true;

        // makes sure that there is only one post running at a time
        // (to prevent racing conditions)
        var runNextPost= function() {
            if (!post_queue.length) {
                $('html').attr('json', 'idle');
                return;
            }
            var post= singleCmd ? post_queue[0] : post_queue.shift();
            if (log) console.log('POST', post.cmd, post.data)
            $.ajax({
                type: 'POST',
                url: '#',
                data: {
                    cmd: post.cmd,
//                    data: $.toJSON(post.data),
                    data: JSON.stringify(post.data),
                },
                dataType: 'json',
                success: function(json) {
                    if (log) console.log('POST RESULT', {cmd:post.cmd, result:json})
                    if (post.fn_prepare) json= post.fn_prepare(json);
                    var fns= posts_data[post.cmd][post.key];
                    forEach(fns, function(fn) {if (fn) fn(json)});
                },
                error: function(XMLHttpRequest, textStatus, errorThrown) {
                    console.error({
                        request:     XMLHttpRequest,
                        errorText:   textStatus,
                        errorThrown: errorThrown,
                    });
                },
                complete: function() {
                    delete posts_data[post.cmd][post.key];
                    post_queue.shift();
                    runNextPost();
                },
                async: true,
                cache: false,
            });
        };

        return function(cmd, key, data, fn_prepare, fn_process) {
//            key= '' + Math.random();
            $('html').attr('json', 'busy');
            if (!posts_data[cmd]) posts_data[cmd]= {};
            if (posts_data[cmd][key]) {
                posts_data[cmd][key].push(fn_process);
                console.debug('queueing', cmd, key)
                return;
            }
            posts_data[cmd][key]= [ fn_process ];

            var queue_empty= post_queue.length === 0;
            post_queue.push({
                cmd: cmd,
                data: data,
                key: key,
                fn_prepare: fn_prepare,
                fn_process: fn_process,
            });
            if (queue_empty) runNextPost();
        };
    })();

    // builds json requests
    var doJsonRequest= function(cmd, params, fn_prepare, fn_process) {

        var key= [];

        // json data of type boolean raises error in perl
        var _convert= function(obj) {
            if (obj == null) return null;
            forEach(obj, function(v, i) {
                switch (typeof v) {
                    case 'boolean':
                        obj[i]= v ? 1 : 0;
                        break

                    case 'object':
                        if (v) v= _convert(v);
                        return // continue

                    case 'undefined':
                    case 'function':
                        v= null;
                        break

                    case 'number':
                        if (isNaN()) v= null;
                        break
                }
                key.push(i, v);
            })
            return obj;
        }
        params= _convert(cloneData(params));
        _singleInstancePost(cmd, key.join(), params, fn_prepare, fn_process);
    };

    // build href for cmd-links
    var buildCmdRef= function(cmd, params) {
        var href= []
        forEach(params, function(param, name) {href.push(name + "=" + encodeURIComponent(param))})
        href.unshift(cmd);
        return '#' + href.join('|');
    };

    // builds array of attribs (key="value") of hash
    var buildAttribs= function(params)  {
        var result= []
        forEach(params, function(param, name) {result.push(name + '="' + encodeURIComponent(param) + '"')})
        return result
    }


// ============================================================================
//      Html Builder Class
// ============================================================================

    var Html= function(pre, post) {
        var items= [];

        this.addItem= function(item) {
            items.push(item);
            return item;
        };

        this.add= function(pre, post) {return this.addItem(new Html(pre, post))};

        this.addItems= function(add_items) {
            items.concat(add_items);
        }

        var rownum= 0;
        var rowclasses= [ 'row1', 'row2' ];

        this.addTable= function(classes) {
            rownum= 0;
            var class= '';
            if (classes) {
                class= ' class="' + classes.join(' ') + '"';
            }
            return this.add('<table' + class + '>', '</table>');
        };

        this.addRow= function(row, class_data) {
            if (!class_data) class_data= [];
            var row_class= [ rowclasses[ rownum++ % rowclasses.length ] ];
            if (class_data.tr) row_class.push(class_data.tr);
            var tr= this.add('<tr class="' + row_class.join(' ') + '">', '</tr>');
            var td_classes= class_data.td || [];
            forEach(row, function(r, i) {tr.add('<td class="' + (td_classes[i] || '') + '">', '</td>').add(r)});
            return row;
        };

        this._render= function() {
            var result= []
            forEach(items, function(item) {result.push(item._render())})
            if (pre)  result.unshift(pre);
            if (post) result.push(post);
            return result.join('');
        };

        this.render= function($el) {
            var html= this._render();
            if ($el) $el.html(html);
            return html;
        };

        return this;
    };


// ============================================================================
//      DelayedFunc class
//      Builds an object that calls the function <fn> delayed by <ms> ms
// ============================================================================

    var DelayedFunc= function(ms, fn) {
        var hTimer;

        if (!fn) console.trace('DelayedFunc: fn is undefined!');

        var stop= function() {
            if (hTimer) clearTimeout(hTimer);
            hTimer= null;
        };

        var me= this;

        var now= function(arg) {
            stop();
            fn.call(me, arg);
        };

        var start= function(arg) {
            stop();
            hTimer= setTimeout(function() { now(arg) }, ms);
        };

        this.start= start;
        this.stop=  stop;
        this.now=   now;
        this.startFn= function() { start() };
        return this;
    };

// ============================================================================
//      Update Marquee
// ============================================================================

    var updateMarquees= function() {
        $('.marquee').marquee({ timeout: 100, speed: 3, end_delay: 5, })
    };

// ============================================================================
//      Misc Manipulation Functions
// ============================================================================

    // replacement for "$(...).html(...)" - much more faster
    var setHtml= function($elems, html) {
        forEach($elems.get(), function(elem) {elem.innerHTML= html});
    };

// ============================================================================
//      Register some global events
// ============================================================================

    Event.add('updatedItem', function(item) {
        if (!item) return;

        item.getDetails(function(item) {
            var uid= item.text('uid');
            setHtml($('.iteminfo[uid="' + uid +'"]').parent(), item.itemHtml());
            updateMarquees();
            Event.fire('updatedListItem');
        });
    });


// ============================================================================
//      Exports
// ============================================================================

    return {
        strcmp: strcmp,
        trim: trim,

        stringSorter: stringSorter,
        formatTime: formatTime,

        mergeData: mergeData,
        cloneData: cloneData,

        doJsonRequest: doJsonRequest,
        buildCmdRef: buildCmdRef,
        buildAttribs: buildAttribs,

        Html: Html,
        DelayedFunc: DelayedFunc,

        updateMarquees: updateMarquees,

        setHtml: setHtml,

        forEach: forEach,
        map: map,
        filter: filter,
    };


// ============================================================================
//      Prologue
// ============================================================================

    })();
});
