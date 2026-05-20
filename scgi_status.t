#!/usr/bin/perl

# (C) Maxim Dounin

# Test for scgi backend returning various status codes.

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

eval { require SCGI; };
plan(skip_all => 'SCGI not installed') if $@;

my $t = Test::Nginx->new()
	->has(qw/http scgi/)->plan(12)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    scgi_param SCGI 1;
    scgi_param REQUEST_URI $request_uri;
    scgi_param REQUEST_METHOD $request_method;

    scgi_read_timeout 10s;
    add_header X-Upstream-Status $upstream_status;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            scgi_pass 127.0.0.1:8081;
        }
    }
}

EOF

$t->run_daemon(\&scgi_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr!^HTTP/1.1 200 !s, 'status 200');
like(http_get('/600'), qr!^HTTP/1.1 600 !s, 'status 600 non-standard');

like(http_get('/status-line'), qr!^HTTP/1.1 204 !s, 'status line');
like(http_get('/status-no-text'), qr!^HTTP/1.1 204 !s, 'status header no text');

like(http_get('/no-status'), qr!^HTTP/1.1 200 !s, 'default status');
like(http_get('/no-status-location'), qr!^HTTP/1.1 302 !s,
	'default status with location');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.1');

# 1xx responses are ignored since 1.29.1, and 101 (Switching Protocols)
# is rejected unless requested by the client

like(http_get('/100'), qr!^HTTP/1.1 200 .*X-Upstream-Status: 200!s,
	'status 100 ignored');
like(http_get('/103'), qr!^HTTP/1.1 200 !s, 'status 103 ignored');

like(http_get('/101'), qr!^HTTP/1.1 502 !s, 'status 101 rejected');
like(http_get('/101-no-text'), qr!^HTTP/1.1 502 !s, 'status 101 rejected');

like(http_get('/001'), qr!^HTTP/1.1 502 !s, 'status 001 rejected');

}

TODO: {
local $TODO = 'not yet'
	unless $t->has_version('1.31.1');
todo_skip 'leaves coredump', 1
	unless $t->has_version('1.31.1')
	or $ENV{TEST_NGINX_UNSAFE};

like(http_get('/split'), qr!^HTTP/1.1 200 .*HTTP-Header: foo!s,
	'status line split between packets');

}

###############################################################################

sub scgi_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $scgi = SCGI->new($server, blocking => 1);
	my ($c, $uri);

	while (my $request = $scgi->accept()) {
		eval { $request->read_env(); };
		next if $@;
		
		$uri = $request->env->{REQUEST_URI};

		$c = $request->connection();

		if ($uri eq '/') {
			$c->print("Status: 200 OK\n\n");

		} elsif ($uri eq '/600') {
			$c->print("Status: 600 Non-standard\n\n");

		} elsif ($uri eq '/status-line') {
			$c->print("HTTP/1.0 204 No content\n\n");

		} elsif ($uri eq '/status-no-text') {
			$c->print("Status: 204\n\n");

		} elsif ($uri eq '/no-status') {
			$c->print("Content-Type: text/html\n\n");

		} elsif ($uri eq '/no-status-location') {
			$c->print("Location: /foobar\n\n");

		} elsif ($uri eq '/100') {
			$c->print("Status: 100 Continue\n\n");
			$c->print("Status: 200 OK\n\n");

		} elsif ($uri eq '/103') {
			$c->print("Status: 103 Early Hints\n");
			$c->print("Link: </foobar>\n\n");
			$c->print("Status: 200 OK\n\n");

		} elsif ($uri eq '/101') {
			$c->print("Status: 101 Switching Protocols\n\n");

		} elsif ($uri eq '/101-no-text') {
			$c->print("Status: 101\n\n");

		} elsif ($uri eq '/001') {
			$c->print("Status: 001 Invalid\n\n");

		} elsif ($uri eq '/split') {
			$c->print("HTTP");
			select undef, undef, undef, 0.1;
			$c->print("-Header: foo\n");
			$c->print("Status: 200 OK\n\n");
		}
	}
}

###############################################################################
