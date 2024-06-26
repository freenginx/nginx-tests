#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for embedded perl module.

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

my $t = Test::Nginx->new()->has(qw/http perl rewrite/)->plan(27)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            set $testvar "TEST";
            perl 'sub {
                use warnings;
                use strict;

                my $r = shift;

                $r->status(204) if $r->args =~ /204/;

                $r->send_http_header("text/plain");

                return OK if $r->header_only;

                my $v = $r->variable("testvar");

                $r->print("testvar: $v\n");

                $r->print("host: ", $r->header_in("Host"), "\n");
                $r->print("xfoo: ", $r->header_in("X-Foo"), "\n");
                $r->print("cookie: ", $r->header_in("Cookie"), "\n");
                $r->print("xff: ", $r->header_in("X-Forwarded-For"), "\n");
                $r->print("connection: ", $r->header_in("Connection"), "\n");

                return OK;
            }';
        }

        location /range {
            perl 'sub {
                use warnings;
                use strict;

                my $r = shift;

                $r->header_out("Content-Length", "42");
                $r->allow_ranges();
                $r->send_http_header("text/plain");

                return OK if $r->header_only;

                $r->print("x" x 42);

                return OK;
            }';
        }

        location /body {
            perl 'sub {
                use warnings;
                use strict;

                my $r = shift;

                if ($r->has_request_body(\&post)) {
                    return OK;
                }

                return HTTP_BAD_REQUEST;

                sub post {
                    my $r = shift;
                    $r->send_http_header;
                    $r->print("body: ", $r->request_body, "\n");
                    $r->print("file: ", $r->request_body_file, "\n");
                }
            }';
        }

        location /discard {
            perl 'sub {
                use warnings;
                use strict;

                my $r = shift;

                $r->discard_request_body;

                $r->send_http_header("text/plain");

                return OK if $r->header_only;

                $r->print("host: ", $r->header_in("Host"), "\n");

                return OK;
            }';
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/'), qr/ 200 .*TEST/s, 'perl response');
like(http_head('/'), qr/ 200 (?!.*TEST)/s, 'perl header_only');
like(http_get('/?204'), qr/ 204 (?!.*TEST)/s, 'perl status, args');

# various $r->header_in() cases

like(http(
	'GET / HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/host: localhost/, 'perl header_in known');

like(http(
	'GET / HTTP/1.0' . CRLF
	. 'X-Foo: foo' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/xfoo: foo/, 'perl header_in unknown');

like(http(
	'GET / HTTP/1.0' . CRLF
	. 'X-Foo: foo' . CRLF
	. 'X-Foo: bar' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/xfoo: foo, bar/, 'perl header_in unknown2');

like(http(
	'GET / HTTP/1.0' . CRLF
	. 'Cookie: foo' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/cookie: foo/, 'perl header_in cookie');

like(http(
	'GET / HTTP/1.0' . CRLF
	. 'Cookie: foo1' . CRLF
	. 'Cookie: foo2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/cookie: foo1; foo2/, 'perl header_in cookie2');

like(http(
	'GET / HTTP/1.0' . CRLF
	. 'X-Forwarded-For: foo' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/xff: foo/, 'perl header_in xff');

like(http(
	'GET / HTTP/1.0' . CRLF
	. 'X-Forwarded-For: foo1' . CRLF
	. 'X-Forwarded-For: foo2' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/xff: foo1, foo2/, 'perl header_in xff2');

like(http(
	'GET / HTTP/1.0' . CRLF
	. 'Connection: close' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/connection: close/, 'perl header_in connection');

like(http(
	'GET / HTTP/1.0' . CRLF
	. 'Connection: close' . CRLF
	. 'Connection: foo' . CRLF
	. 'Host: localhost' . CRLF . CRLF
), qr/connection: close, foo/, 'perl header_in connection2');

# headers_out content-length tests with range filter

like(http_get('/range'), qr/Content-Length: 42.*^x{42}$/ms,
	'perl header_out content-length');

like(http(
	'GET /range HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF
	. 'Range: bytes=0-1' . CRLF . CRLF
), qr/Content-Length: 2.*^xx$/ms, 'perl header_out content-length range');

like(http(
	'GET /range HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF
	. 'Range: bytes=0-1,3-5' . CRLF . CRLF
), qr/Content-Length: (?!42).*^xx\x0d.*^xxx\x0d/ms,
	'perl header_out content-length multipart');

like(http(
	'GET /range HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF
	. 'Range: bytes=100000-' . CRLF . CRLF
), qr|^\QHTTP/1.1 416\E.*(?!xxx)|ms, 'perl range not satisfiable');

like(http(
	'GET / HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF
	. 'If-Match: tt' . CRLF . CRLF
), qr|200 OK|ms, 'perl precondition failed');

# various request body tests

like(http_get('/body'), qr/400 Bad Request/, 'perl no body');

like(http(
	'GET /body HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF
	. 'Content-Length: 10' . CRLF . CRLF
	. '1234567890'
), qr/body: 1234567890/, 'perl body preread');

like(http(
	'GET /body HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF
	. 'Content-Length: 10' . CRLF . CRLF,
	sleep => 0.1,
	body => '1234567890'
), qr/body: 1234567890/, 'perl body late');

like(http(
	'GET /body HTTP/1.0' . CRLF
	. 'Host: localhost' . CRLF
	. 'Content-Length: 10' . CRLF . CRLF
	. '12345',
	sleep => 0.1,
	body => '67890'
), qr/body: 1234567890/, 'perl body split');

like(http(
	'GET /body HTTP/1.1' . CRLF
	. 'Host: localhost' . CRLF
	. 'Connection: close' . CRLF
	. 'Transfer-Encoding: chunked' . CRLF . CRLF
	. 'a' . CRLF
	. '1234567890' . CRLF
	. '0' . CRLF . CRLF
), qr/body: 1234567890/, 'perl body chunked');

like(http(
	'GET /body HTTP/1.1' . CRLF
	. 'Host: localhost' . CRLF
	. 'Connection: close' . CRLF
	. 'Transfer-Encoding: chunked' . CRLF . CRLF,
	sleep => 0.1,
	body => 'a' . CRLF . '1234567890' . CRLF . '0' . CRLF . CRLF
), qr/body: 1234567890/, 'perl body chunked late');

like(http(
	'GET /body HTTP/1.1' . CRLF
	. 'Host: localhost' . CRLF
	. 'Connection: close' . CRLF
	. 'Transfer-Encoding: chunked' . CRLF . CRLF
	. 'a' . CRLF
	. '12345',
	sleep => 0.1,
	body => '67890' . CRLF . '0' . CRLF . CRLF
), qr/body: 1234567890/, 'perl body chunked split');

like(http(
	'GET /discard HTTP/1.1' . CRLF
	. 'Host: localhost' . CRLF
	. 'Connection: close' . CRLF
	. 'Transfer-Encoding: chunked' . CRLF . CRLF
	. 'a' . CRLF
	. '1234567890' . CRLF
	. '0' . CRLF . CRLF
), qr/host: localhost/, 'perl body discard');

like(http(
	'GET /discard HTTP/1.1' . CRLF
	. 'Host: localhost' . CRLF
	. 'Connection: close' . CRLF
	. 'Transfer-Encoding: chunked' . CRLF . CRLF
	. 'ak' . CRLF
	. '1234567890' . CRLF
	. '0' . CRLF . CRLF
), qr/400 Bad Request/, 'perl body discard bad chunk');

like(http(
	'GET /body HTTP/1.1' . CRLF
	. 'Host: localhost' . CRLF
	. 'Connection: close' . CRLF
	. 'Transfer-Encoding: chunked' . CRLF . CRLF
	. 'ak' . CRLF
	. '1234567890' . CRLF
	. '0' . CRLF . CRLF
), qr/400 Bad Request/, 'perl body bad chunk');

###############################################################################
