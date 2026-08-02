#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy module with upstream variables.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache rewrite/)->plan(22)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8082 max_fails=0;
        server 127.0.0.1:8081 backup;
    }

    proxy_cache_path cache keys_zone=one:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:8081/stub;
            add_header X-Proxy-Host $proxy_host;
            add_header X-Proxy-Port $proxy_port;
            add_header X-Proxy-Forwarded $proxy_add_x_forwarded_for;
            add_header X-Upstream-Addr $upstream_addr;
            add_header X-Upstream-Status $upstream_status;
        }

        location /time {
            proxy_pass http://127.0.0.1:8081/stub;
            add_header X-Connect-Time $upstream_connect_time;
            add_header X-Header-Time $upstream_header_time;
            add_header X-Response-Time $upstream_response_time;
        }

        location /next {
            proxy_pass http://u/stub;
            add_header X-Connect-Time $upstream_connect_time;
            add_header X-Header-Time $upstream_header_time;
            add_header X-Response-Time $upstream_response_time;
        }

        location /length {
            proxy_pass http://127.0.0.1:8081/stub_length;
            add_trailer X-Response-Length $upstream_response_length;
            add_trailer X-Bytes-Received $upstream_bytes_received;
            add_trailer X-Bytes-Sent $upstream_bytes_sent;
        }

        location /header {
            proxy_pass http://127.0.0.1:8081/stub_header;
            add_header X-Header $upstream_http_foo;
        }

        location /trailer {
            proxy_pass http://127.0.0.1:8081/stub_trailer;
            proxy_http_version 1.1;
            add_header X-Trailer $upstream_trailer_foo;
        }

        location /cookie {
            proxy_pass http://127.0.0.1:8081/stub_cookie;
            add_header X-Cookie $upstream_cookie_foo;
        }

        location /cache {
            proxy_pass http://127.0.0.1:8081/stub;
            proxy_cache one;
            proxy_cache_key foo;
            proxy_cache_valid 200 1m;
            add_header X-Cache-Status $upstream_cache_status;
            add_header X-Cache-Key $upstream_cache_key;
            add_header X-Cache-Age $upstream_cache_age;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
        }

        location /stub_length {
            add_header X-Length $request_length;
            limit_rate 800;
        }

        location /stub_header {
            add_header Foo foo;
            add_header Foo bar;
        }

        location /stub_trailer {
            add_trailer Foo foo;
            add_trailer Foo bar;
        }

        location /stub_cookie {
            add_header Set-Cookie foo=foo;
        }
    }

    server {
        listen       127.0.0.1:8082;
        server_name  localhost;
        return 444;
    }
}

EOF

$t->write_file('stub', '');
$t->write_file('stub_length', '1234567890' x 100);
$t->write_file('stub_header', '');
$t->write_file('stub_trailer', '');
$t->write_file('stub_cookie', '');
$t->run();

###############################################################################

my $r;

# $proxy_host
# $proxy_port
# $proxy_add_x_forwarded_for

$r = get('/');
like($r, qr/X-Proxy-Host: 127\.0\.0\.1:/, '$proxy_host');
like($r, qr/X-Proxy-Port: \d+/, '$proxy_port');
like($r, qr/X-Proxy-Forwarded: 127\.0\.0\.1/, '$proxy_add_x_forwarded_for');

like(get('/', 'X-Forwarded-For: 192.0.2.1'),
	qr/X-Proxy-Forwarded: 192\.0\.2\.1, 127\.0\.0\.1/,
        '$proxy_add_x_forwarded_for add');

# $upstream_addr
# $upstream_status

$r = get('/');
like($r, qr/X-Upstream-Addr: 127\.0\.0\.1:/, '$upstream_addr');
like($r, qr/X-Upstream-Status: 200/, '$upstream_status');

# $upstream_connect_time
# $upstream_header_time
# $upstream_response_time

# Note that $upstream_response_time is only available after the upstream
# request is finalized.

$r = get('/time');
like($r, qr/X-Connect-Time: \d\./, '$upstream_connect_time');
like($r, qr/X-Header-Time: \d\./, '$upstream_header_time');
like($r, qr/X-Response-Time: -/, '$upstream_response_time');

# Since first request fails before getting a header, $upstream_header_time
# will be only available for the second request, after switching the next
# upstream server.  And $upstream_response_time is only available for
# the first request, but not available for the second one, since it is
# not yet finalized.

$r = get('/next');
like($r, qr/X-Connect-Time: \d\.\d+, \d\.\d+/,
	'$upstream_connect_time next upstream');
like($r, qr/X-Header-Time: -, \d\.\d+/,
	'$upstream_header_time next upstream');
like($r, qr/X-Response-Time: \d\.\d+, -/,
	'$upstream_response_time next upstream');

# $upstream_response_length
# $upstream_bytes_received
# $upstream_bytes_sent

# Final values are only available after the response is received, so
# we use trailers here.  Note that this requires HTTP/1.1 request.

$r = get('/length');
like($r, qr/X-Response-Length: 1000/, '$upstream_response_length');
like($r, qr/X-Bytes-Received: \d+/, '$upstream_bytes_received');
like($r, qr/X-Length: (\d+).*X-Bytes-Sent: \1/s, '$upstream_bytes_sent');

# $upstream_http_
# $upstream_trailer_

like(get('/header'), qr/X-Header: foo, bar/, '$upstream_http_foo');

TODO: {
local $TODO = 'no trailers support in proxy yet';

like(get('/trailer'), qr/X-Trailer: foo, bar/, '$upstream_trailer_foo');

}

# $upstream_cookie_

like(get('/cookie'), qr/X-Cookie: foo/, '$upstream_cookie_foo');

# $upstream_cache_status
# $upstream_cache_key
# $upstream_cache_age

# Note that the $upstream_cache_last_modified and $upstream_cache_etag
# variables are internal, and therefore not tested here.

$r = get('/cache');
like($r, qr/X-Cache-Status: MISS/, '$upstream_cache_status');
like($r, qr/X-Cache-Key: foo/, '$upstream_cache_key');

$r = get('/cache');
like($r, qr/X-Cache-Status: HIT/, '$upstream_cache_status hit');
like($r, qr/X-Cache-Age: \d+/, '$upstream_cache_age');

###############################################################################

sub get {
	my ($url, @headers) = @_;
	return http(
		"GET $url HTTP/1.1" . CRLF .
		'Host: localhost' . CRLF .
		'Connection: close' . CRLF .
		join(CRLF, @headers) . CRLF . CRLF
	);
}

###############################################################################
