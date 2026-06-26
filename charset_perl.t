#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for charset filter, extended tests using embedded perl.

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

my $t = Test::Nginx->new()->has(qw/http charset perl/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    charset test;
    source_charset utf-8;

    charset_map test utf-8 {
        43  C2A9 ;      # (C)
        54  E284A2 ;    # trade mark sign
    }

    postpone_output 0;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            perl 'sub {
                my $r = shift;
                $r->send_http_header("text/html");
                return OK if $r->header_only;

                # 2-byte character

                $r->print("\xc2\xa9");
                $r->print("\xc2");
                $r->print("\xa9");

                # 3-byte character

                $r->print("\xe2\x84\xa2");
                $r->print("\xe2");
                $r->print("\x84");
                $r->print("\xa2");

                # 4-byte character

                $r->print("\xf0\x90\x80\x80");
                $r->print("\xf0");
                $r->print("\x90");
                $r->print("\x80");
                $r->print("\x80");

                return OK;
            }';
        }

        location /invalid {
            perl 'sub {
                my $r = shift;
                $r->send_http_header("text/html");
                return OK if $r->header_only;

                # 2-byte invalid character

                $r->print("\xc2\x61");
                $r->print("\xc2");
                $r->print("\x61");

                # 3-byte invalid character

                $r->print("\xe2\x61\x61");
                $r->print("\xe2");
                $r->print("\x61");
                $r->print("\x61");

                # 4-byte invalid character

                $r->print("\xf0\x61\x61\x61");

                $r->print("\xf0");
                $r->print("\x61");
                $r->print("\x61");
                $r->print("\x61");

                return OK;
            }';
        }
    }
}

EOF

$t->run();

###############################################################################

TODO: {
local $TODO = 'not yet'
        unless $t->has_version('1.31.1') or $t->has_version('1.30.1');
todo_skip 'might coredump', 1
	unless $t->has_version('1.31.1') or $t->has_version('1.30.1')
	or $ENV{TEST_NGINX_UNSAFE};

like(http_get('/multi'), qr/^CCTT&#65536;&#65536;$/m, 'multiple buffers');

}

TODO: {
local $TODO = 'not yet'
        unless $t->has_version('1.31.3');
todo_skip 'might coredump', 1
	unless $t->has_version('1.31.3')
	or $ENV{TEST_NGINX_UNSAFE};

like(http_get('/invalid'), qr/^\Q???a?a?aa?aa\E$/m,
	'invalid in multiple buffers');

}

###############################################################################
