#!/usr/bin/perl

# (C) Maxim Dounin

# Test for fastcgi header params.

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

eval { require FCGI; };
plan(skip_all => 'FCGI not installed') if $@;
plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http fastcgi/)->plan(4)
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
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param HTTP_X_BLAH "blah";
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get_headers('/'), qr/SEE-THIS/,
	'fastcgi request with many ignored headers');

my $r;

$r = http(<<EOF);
GET / HTTP/1.0
Host: localhost
X-Forwarded-For: foo
X-Forwarded-For: bar
X-Forwarded-For: bazz
Cookie: foo
Cookie: bar
Cookie: bazz
Foo: foo
Foo: bar
Foo: bazz

EOF

like($r, qr/X-Forwarded-For: foo, bar, bazz/,
	'fastcgi with multiple X-Forwarded-For headers');

like($r, qr/X-Cookie: foo; bar; bazz/,
	'fastcgi with multiple Cookie headers');

like($r, qr/X-Foo: foo, bar, bazz/,
	'fastcgi with multiple unknown headers');

###############################################################################

sub http_get_headers {
	my ($url, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.0
Host: localhost
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header

EOF
}

###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:' . port(8081), 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my $count;
	while( $request->Accept() >= 0 ) {
		$count++;

		my $xfwd = $ENV{HTTP_X_FORWARDED_FOR} || '';
		my $cookie = $ENV{HTTP_COOKIE} || '';
		my $foo = $ENV{HTTP_FOO} || '';

		print <<EOF;
Location: http://localhost/redirect
Content-Type: text/html
X-Forwarded-For: $xfwd
X-Cookie: $cookie
X-Foo: $foo

SEE-THIS
$count
EOF
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
