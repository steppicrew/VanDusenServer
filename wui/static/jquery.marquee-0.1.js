
// options:
//      timeout: time in ms between two marquee updates
//      speed: number of pixels text is moved per cycle
//      end_delay: number of cycles to wait before reversing direction

;jQuery.fn.marquee= function(options, param, value) {
    var Marquee= function(obj, options) {
        if ($(obj).find('.innerMarquee').length) return true;
        $(obj).html('<div class="innerMarquee">' + $(obj).html() + '</div>');

        var marquee= $(obj).children()[0];
        var timer= null;
        var speed= options['speed'] || 3;
        var timeout= options['timeout'] || 100;
        var end_delay= options['end_delay'] || 0;
        var left= 0;
        var direction= -1;

        $(marquee).css('left', 0);

        var off= function() {
            if (timer) {
                clearInterval(timer);
                timer= null;
                left= 0;
                direction= -1;
                $(marquee).css('left', 0);
            };
        };
        var on= function() {
            if (timer) off();
            // calculate width
            $(marquee).css('position', 'absolute');
            var real_width= marquee.clientWidth;
            $(marquee).css('position', 'relative');
            var show_width= marquee.clientWidth;
            var left_min= show_width - real_width;
            if (left_min >= 0) return;
            var end_pause= 0;

            timer= setInterval(
                function() {
                    if (end_pause) {
                        if (end_pause++ > end_delay) {
                            direction= -direction;
                            end_pause= 0;
                        }
                        else return;
                    }

                    left += speed * direction;

                    if (left <= left_min) {
                        end_pause= 1;
                        left= left_min;
                    }
                    else if (left >= 0) {
                        end_pause= 1;
                        left= 0;
                    }
                    $(marquee).css('left', left);
                },
                timeout
            );
        };
        var option= function(name, value) {
            switch (name) {
                case 'timeout':
                    if (value) {
                        timeout= value;
                        if (timer) on();
                    }
                    else {
                        return timeout;
                    }
                    break;
                case 'speed':
                    if (value) {
                        speed= value;
                    }
                    else {
                        return speed;
                    }
                    break;
                case 'end_delay':
                    if (value) {
                        end_delay= value;
                    }
                    else {
                        return end_delay;
                    }
                    break;
            }
        };

        this.on= on;
        this.off= off;
        this.option= option;
    };

    if (!options) options= {};

    if (typeof options === 'object') {
        return this.each(function() {
            var m= jQuery.data(this, 'marquee-data');
            if (m) return true;
            jQuery.data(this, 'marquee-data', new Marquee(this, options));
            return true;
        });
    }

    if (options === 'option' && value) {
        var m= jQuery.data(this[0], 'marquee-data');
        if (m) return m.option(param, value);
        return null;
    }

    this.each(function() {
        var m= jQuery.data(this, 'marquee-data');
        if (!m) return true;
        if (!m[options]) {
            console.error('Marquee has no "' + options + '" option!');
            return false;
        }
        m[options](param)
    });
};

