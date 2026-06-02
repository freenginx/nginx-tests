#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for rewrite set.

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

my $t = Test::Nginx->new()->has(qw/http rewrite ssi/)->plan(10);

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

        location /string {
            set $temp "set_string";
            return 200 "X${temp}X";
        }

        location /variable/ {
            set $temp "set_$uri";
            return 200 "X${temp}X";
        }

        location ~ ^(/capture/.*) {
            set $temp "set_$1";
            return 200 "X${temp}X";
        }

        location /if/ {
            if ($uri ~ "(.*)") {
                set $temp "set_$1";
            }
            return 200 "X${temp}X";
        }

        location /rewrite/ {
            rewrite (.*) $1;
            if ($uri ~ "(.*)") {
                set $temp "set_$1";
            }
            return 200 "X${temp}X";
        }

        location /args/ {
            rewrite (.*) $1?args;
            if ($uri ~ "(.*)") {
                set $temp "set_$1";
            }
            return 200 "X${temp}X";
        }

        location /t1 {
            set $http_foo "set_foo";
            ssi on;
            return 200 'X<!--#echo var="http_foo" -->X';
        }

        location /t2 {
            ssi on;
            return 200 'X<!--#echo var="http_bar" -->X';
        }

        location /t3 {
            ssi on;
            return 200 'X<!--#echo var="http_baz" -->X';
        }

        location /t4 {
            set $http_connection "bar";
            return 200 "X${http_connection}X\n";
        }

        location /other {
            # set in other context
            set $http_bar "set_bar";
        }
    }
}

EOF

$t->run();

###############################################################################

# basic set operations

like(http_get('/string'), qr/Xset_stringX/, 'set string');
like(http_get('/variable/%20x'), qr!Xset_/variable/ xX!, 'set variable');
like(http_get('/capture/%20x'), qr!Xset_/capture/%20xX!, 'set capture');
like(http_get('/if/%20x'), qr!Xset_/if/%20xX!, 'set capture after if');

TODO: {
local $TODO = 'not yet'
	unless $t->has_version('1.31.1');

# set after a rewrite, used to loss quoting
# due to e->quote being reset

like(http_get('/rewrite/%20x'), qr!Xset_/rewrite/%20xX!,
	'set capture after rewrite');

}

TODO: {
local $TODO = 'not yet'
	unless $t->has_version('1.31.1');
todo_skip 'might coredump', 1
	unless $t->has_version('1.31.1') or $t->has_version('1.30.1')
	or $ENV{TEST_NGINX_UNSAFE};

# set after a rewrite with arguments,
# used to incorrectly allocate buffer due to e->is_args set
# but not propagated to length calculations

like(http_get('/args/%20x'), qr!Xset_/args/%20xX!,
	'set capture after rewrite with arguments');

}

# non-indexed access of prefixed variables

like(http_get_extra('/t1.html', 'Foo: http_foo'), qr/Xset_fooX/,
	'set in this context');
like(http_get_extra('/t2.html', 'Bar: http_bar'), qr/Xhttp_barX/,
	'set in other context');
like(http_get_extra('/t3.html', 'Baz: http_baz'), qr/Xhttp_bazX/, 'not set');
like(http_get('/t4.html'), qr/XbarX/, 'set get in return');

###############################################################################

sub http_get_extra {
	my ($uri, $extra) = @_;
	return http(<<EOF);
GET $uri HTTP/1.0
$extra

EOF
}

###############################################################################
