#!/usr/bin/perl

# (C) Maxim Dounin

# Stream tests for access_log, script execution.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/stream stream_map stream_return http rewrite/)->plan(1)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    log_format map_capture "start $capture $map_capture end";

    map $pid $map_capture {
        ~(?<capture>.*) $capture;
    }

    server {
        listen 127.0.0.1:8080;
        return ok;

        access_log map.log map_capture;
    }
}

EOF

$t->run();

###############################################################################

TODO: {
todo_skip 'might coredump', 1
	unless $t->has_version('1.31.3')
	or $ENV{TEST_NGINX_UNSAFE};
local $TODO = 'not yet', $t->todo_alerts();

# map with side effects might result in incorrect buffer size
# and buffer overrun

http_get('/');

$t->stop();

my $log = $t->read_file('map.log');

like($log, qr!start /map /map end!, 'log and map with side effects');

}

###############################################################################
