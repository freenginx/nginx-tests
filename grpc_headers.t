#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for grpc module, grpc_set_header directive.

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
	->has(qw/http http_v2 grpc rewrite/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $uri $map_capture {
        ~(?<capture>.*) $capture;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            grpc_pass 127.0.0.1:8081;
            grpc_set_header X-Blah "blah $capture $map_capture end";
        }

        location /multi {
            grpc_pass 127.0.0.1:8081;
            grpc_set_header X-Blah1 "$capture";
            grpc_set_header X-Blah2 "$capture";
            grpc_set_header X-Blah3 "$capture";
            grpc_set_header X-Blah4 "$capture";
            grpc_set_header X-Blah5 "$capture";
            grpc_set_header X-Blah6 "$capture";
            grpc_set_header X-Blah "blah $map_capture end";
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        http2 on;

        location / {
            return 200 "$http_x_blah\n";
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

like(http_get('/test-long-uri'), qr!blah .* /test-long-uri end!,
	'grpc_set_header and map with side effects');

like(http_get('/multi'), qr!blah /multi end!,
	'grpc_set_header and map with side effects, multiple headers');

}

###############################################################################
