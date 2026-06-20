#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for grpc module, grpc_set_header directive.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http http_v2 grpc rewrite/)->plan(7)
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

    large_client_header_buffers 2 4m;
    ignore_invalid_headers off;

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

        location /long {
            grpc_pass 127.0.0.1:8081;
            grpc_set_header Host "";
            grpc_set_header TE "";
            grpc_set_header Content-Length "";
            grpc_set_header Connection "";
        }

        location /long_set {
            grpc_pass 127.0.0.1:8081;
            grpc_set_header Host "";
            grpc_set_header TE "";
            grpc_set_header Content-Length "";
            grpc_set_header Connection "";
            grpc_set_header X-Long $a;
            set $a $args;
            set $a $a$a$a$a$a$a$a$a$a$a;
            set $a $a$a$a$a$a$a$a$a$a$a;
            set $a $a$a$a$a$a$a$a$a$a$a;
            set $a $a$a$a$a$a$a$a$a$a$a;
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

TODO: {
todo_skip 'might coredump', 4
	unless $t->has_version('1.31.3')
	or $ENV{TEST_NGINX_UNSAFE};
local $TODO = 'not yet' unless $t->has_version('1.31.3');

# gRPC module reserves NGX_HTTP_V2_INT_OCTETS (4 bytes) for string lengths,
# and strings longer than NGX_HTTP_V2_MAX_FIELD (~2 megabytes) will use
# one more byte for string length

like(http_get('/long?' . ('~' x 2097279)), qr!HTTP/1.!, 'too long :path');

like(http('GE' . ('X' x 2097279) . ' /long?' . ('~' x 16513)
	. ' HTTP/1.0' . CRLF . CRLF),
	qr!HTTP/1.!, 'too long :method');

like(http('GET /long?' . ('~' x 16513) . ' HTTP/1.0' . CRLF
	. 'F' . ('~' x 2097279) . ': ' . ('~' x 16513) . CRLF . CRLF),
	qr!HTTP/1.!, 'too long header name');

like(http('GET /long?' . ('~' x 16513) . ' HTTP/1.0' . CRLF
	. 'F' . ('~' x 16513) . ': ' . ('~' x 2097279) . CRLF . CRLF),
	qr!HTTP/1.!, 'too long header value');

}

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.3');

# this cannot overflow, since header name is short, but still has
# to be rejected

like(http_get('/long_set?' . ('~' x 210)), qr!500 Internal!,
	'too long set header value');

}

###############################################################################
