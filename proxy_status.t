#!/usr/bin/perl

# (C) Maxim Dounin

# Test for http backend returning various status codes.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF LF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_read_timeout 10s;
        add_header X-Upstream-Status $upstream_status;

        location / {
            proxy_pass http://127.0.0.1:8081;
        }

        location /allow09/ {
            proxy_pass http://127.0.0.1:8081/;
            proxy_allow_http09 on;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->try_run('no proxy_allow_http09')->plan(14);
$t->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr!^HTTP/1.1 200 !s, 'status 200');
like(http_get('/600'), qr!^HTTP/1.1 600 !s, 'status 600 non-standard');

like(http_get('/http10'), qr!^HTTP/1.1 200 !s, 'http 1.0 200');
like(http_get('/duplicate'), qr!^HTTP/1.1 200 !s, 'duplicate status ignored');

# status line without text and trailing space,
# invalid but currently accepted

like(http_get('/notext'), qr!^HTTP/1.1 200!s, 'status without text');

# HTTP/0.9 is disabled by default since 1.29.1

like(http_get('/http09'), qr!^HTTP/1.1 502 !s, 'http 0.9');
like(http_get('/allow09/http09'), qr!^HTTP/1.1 200 .*HTTP/0.9!s,
	'http 0.9 allowed');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.1')
	or $t->has_version('1.30.1');

like(http_get('/allow09/split'), qr!^HTTP/1.1 200 OK.*HTTP/0.9!s,
	'http 0.9 split between packets');

}

# spaces between digits not allowed since 1.29.1

like(http_get('/spaces'), qr!^HTTP/1.1 502 !s, 'status with spaces rejected');
like(http_get('/allow09/spaces'), qr!^HTTP/1.1 200 OK.*2 0 0 OK!s,
	'status with spaces as http 0.9');

# 1xx responses are ignored since 1.29.1, and 101 (Switching Protocols)
# is rejected unless requested by the client and configured

like(http_get('/100'), qr!^HTTP/1.1 200 .*X-Upstream-Status: 200!s,
	'status 100 ignored');
like(http_get('/103'), qr!^HTTP/1.1 200 !s, 'status 103 ignored');

like(http_get('/101'), qr!^HTTP/1.1 502 !s, 'status 101 rejected');

like(http_get('/001'), qr!^HTTP/1.1 502 !s, 'status 001 rejected');

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

		if ($uri eq '/') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF . CRLF;

		} elsif ($uri eq '/600') {

			print $client
				'HTTP/1.1 600 Non-standard' . CRLF .
				'Connection: close' . CRLF . CRLF;

		} elsif ($uri eq '/http10') {

			print $client
				'HTTP/1.0 200 OK' . CRLF .
				'Connection: close' . CRLF . CRLF;

		} elsif ($uri eq '/duplicate') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'HTTP/1.1 204 No content' . CRLF .
				'Connection: close' . CRLF . CRLF;

		} elsif ($uri eq '/notext') {

			print $client
				'HTTP/1.1 200' . LF .
				'Connection: close' . CRLF . CRLF;

		} elsif ($uri =~ m!/http09!) {

			print $client 'It is HTTP/0.9 response' . CRLF;

		} elsif ($uri =~ m!/split!) {

			print $client 'HTTP';
			select undef, undef, undef, 0.1;
			print $client '/0.9 split between packets'. CRLF;

		} elsif ($uri =~ m!/spaces!) {

			print $client
				'HTTP/1.1 2 0 0 OK' . CRLF .
				'Connection: close' . CRLF . CRLF;

		} elsif ($uri eq '/100') {

			print $client
				'HTTP/1.1 100 Continue' . CRLF . CRLF .
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF . CRLF;

		} elsif ($uri eq '/103') {

			print $client
				'HTTP/1.1 103 Early Hints' . CRLF .
				'Link: </foobar>' . CRLF . CRLF .
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF . CRLF;

		} elsif ($uri eq '/101') {

			print $client
				'HTTP/1.1 101 Switching' . CRLF . CRLF .
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF . CRLF;

		} elsif ($uri eq '/001') {

			print $client
				'HTTP/1.1 001 Invalid' . CRLF . CRLF .
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: close' . CRLF . CRLF;

		}

		close $client;
	}
}

###############################################################################
