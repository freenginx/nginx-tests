#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for stream named captures.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/stream stream_return stream_map http rewrite/)
	->plan(6);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    map 0 $map {
        default map;
    }

    map 0 $capture {
        ~(?<map>.*) $map;
    }

    map 0 $capture_late {
        ~(?<late>.*) $late;
    }

    map 0 $late {
        default map;
    }

    map 0 $capture_prefix {
        ~(?<proxy_protocol_tlv_0x01>.*) $proxy_protocol_tlv_0x01;
    }

    server {
        listen  127.0.0.1:8090;
        return  $map;
    }

    server {
        listen  127.0.0.1:8091;
        return  $capture;
    }

    server {
        listen  127.0.0.1:8092;
        return  $late;
    }

    server {
        listen  127.0.0.1:8093;
        return  $capture_late;
    }

    server {
        listen  127.0.0.1:8094 proxy_protocol;
        return  $proxy_protocol_tlv_0x01;
    }

    server {
        listen  127.0.0.1:8095 proxy_protocol;
        return  $capture_prefix;
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

is(stream('127.0.0.1:' . port(8090))->read(), 'map', 'value from map');

}

is(stream('127.0.0.1:' . port(8091))->read(), '0',
	'value from capture overrides map');

is(stream('127.0.0.1:' . port(8092))->read(), 'map', 'value from later map');
is(stream('127.0.0.1:' . port(8093))->read(), '0',
	'value from capture overrides later map');

my $pp = "\x0D\x0A\x0D\x0A\x00\x0D\x0A\x51\x55\x49\x54\x0A"
	. "\x21"
	. "\x11"
	. "\x00\x12"
	. "\x00\x00\x00\x00"
	. "\x00\x00\x00\x00"
	. "\x00\x00\x00\x00"
	. "\x01\x00\x03tlv";

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.3');

is(stream('127.0.0.1:' . port(8094))->io($pp), 'tlv', 'value from tlv');

}

is(stream('127.0.0.1:' . port(8095))->io($pp), '0',
	'value from capture overrides tlv');

###############################################################################
