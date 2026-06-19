#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for proxy_set_body.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite map/)->plan(4)
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
            proxy_pass http://127.0.0.1:8080/body;
            proxy_set_body "body";
        }

        location /p1 {
            proxy_pass http://127.0.0.1:8080/x1;
            proxy_set_body "body";
        }

        location /p2 {
            proxy_pass http://127.0.0.1:8080/body;
            proxy_set_body "body two";
        }

        location /x1 {
            add_header X-Accel-Redirect /p2;
            return 204;
        }

        location /map {
            proxy_pass http://127.0.0.1:8080/body;
            proxy_set_body "body $capture $map_capture end";
        }

        location /map_header {
            proxy_pass http://127.0.0.1:8080/body;
            proxy_set_header X-Header "header $capture $map_capture end";
        }

        location /body {
            add_header X-Body $request_body;
            add_header X-Header $http_x_header;
            proxy_pass http://127.0.0.1:8080/empty;
        }

        location /empty {
            return 204;
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/'), qr/X-Body: body/, 'proxy_set_body');
like(http_get('/p1'), qr/X-Body: body two/, 'proxy_set_body twice');

TODO: {
todo_skip 'might coredump', 2
	unless $t->has_version('1.31.3')
	or $ENV{TEST_NGINX_UNSAFE};
local $TODO = 'not yet', $t->todo_alerts();

like(http_get('/map'), qr!X-Body: body .* /map end!,
	'proxy_set_body and map with side effects');
like(http_get('/map_header'), qr!X-Header: header .* /map_header end!,
	'proxy_set_header and map with side effects');

}

###############################################################################
