#!/usr/bin/perl

# (C) Vladimir Kokshenev
# (C) Nginx, Inc.

# Tests for stream set directive.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/stream stream_return stream_map stream_set http rewrite/)
	->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    map 0 $map_var {
        default "original";
    }

    map 0 $map_capture {
        ~(?<capture>.*) $capture;
    }

    server {
        listen  127.0.0.1:8082;
        return  $map_var:$set_var;

        set $set_var $map_var;
        set $map_var "new";
    }

    server {
        listen  127.0.0.1:8083;
        return  $set_var;
    }

    server {
        listen  127.0.0.1:8084;
        return  "$capture $map_capture";
    }
}

EOF

$t->run();

###############################################################################

is(stream('127.0.0.1:' . port(8082))->read(), 'new:original', 'set');
is(stream('127.0.0.1:' . port(8083))->read(), '', 'uninitialized variable');

TODO: {
todo_skip 'might coredump', 1
	unless $t->has_version('1.31.3')
	or $ENV{TEST_NGINX_UNSAFE};
local $TODO = 'not yet', $t->todo_alerts()
	unless $t->has_version('1.31.4');

is(stream('127.0.0.1:' . port(8084))->read(), '0 0',
	'set and map with side effects');

}

###############################################################################
