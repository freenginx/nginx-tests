#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for rewrite module, named captures.

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

my $t = Test::Nginx->new()->has(qw/http rewrite map/)->plan(6)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $uri $map {
        default map;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /map {
            return 200 "value: $map\n";
        }

        location /map/rewrite {
            rewrite ^(?<map>.*) /;
            return 200 "value: $map\n";
        }

        location /later {
            return 200 "value: $late\n";
        }

        location /later/rewrite {
            rewrite ^(?<late>.*) /;
            return 200 "value: $late\n";
        }

        location /prefix {
            return 200 "value: $arg_foo\n";
        }

        location /prefix/rewrite {
            rewrite ^(?<arg_foo>.*) /;
            return 200 "value: $arg_foo\n";
        }
    }

    map $uri $late {
        default map;
    }
}

EOF

$t->run();

###############################################################################

# named captures used to override the v->get_handler if it was previously
# set by a changeable variable, such as provided by map, and did not use
# the NGX_HTTP_VAR_WEAK flag, thus overriding corresponding prefix variables

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.3');

like(http_get('/map'), qr!value: map!, 'value from map');

}

like(http_get('/map/rewrite'), qr!value: /map/rewrite!,
	'value from capture overrides map');

like(http_get('/later'), qr!value: map!, 'value from later map');
like(http_get('/later/rewrite'), qr!value: /later/rewrite!,
	'value from capture overrides later map');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.3');

like(http_get('/prefix?foo=arg'), qr!value: arg!, 'value from arg');

}

like(http_get('/prefix/rewrite?foo=arg'), qr!value: /prefix/rewrite!,
	'value from capture overrides arg');

###############################################################################
