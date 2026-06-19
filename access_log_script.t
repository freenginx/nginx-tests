#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for access_log, script execution.

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

my $t = Test::Nginx->new()->has(qw/http rewrite map/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format map_capture "start $capture $map_capture end";
    log_format map_volatile
               "start $map_volatile $document_root $realpath_root end";

    map $uri $map_capture {
        ~(?<capture>.*) $capture;
    }

    map prefix:$capture $map_volatile {
        volatile;
        ~(?<capture>.*) $capture;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /map {
            access_log map.log map_capture;
        }

        location /map_volatile {
            root html/$pid;
            access_log map.log map_volatile;
        }
    }
}

EOF

$t->run();

###############################################################################

TODO: {
todo_skip 'might coredump', 2
	unless $t->has_version('1.31.3')
	or $ENV{TEST_NGINX_UNSAFE};
local $TODO = 'not yet', $t->todo_alerts();

# map with side effects might result in incorrect buffer size
# and buffer overrun

http_get('/map');

# using a non-cacheable variable might result in incorrect buffer
# size and buffer overrun

http_get('/map_volatile');

$t->stop();

my $log = $t->read_file('map.log');

like($log, qr!start /map /map end!, 'log and map with side effects');
like($log, qr!start prefix: .* end!, 'log and volatile map');

}

###############################################################################
