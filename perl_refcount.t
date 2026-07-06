#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for embedded perl module, various reference counting tests.

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

my $t = Test::Nginx->new()->has(qw/http perl/)->plan(6)
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

        location /sleep {
            perl 'sub {
                my $r = shift;

                $r->sleep(100, eval q!sub {
                    my $r = shift;
                    $r->send_http_header;
                    $r->print("it works");
                    return OK;
                }!);

                return OK;
            }';
        }

        location /body {
            perl 'sub {
                my $r = shift;

                $r->has_request_body(eval q!sub {
                    my $r = shift;
                    $r->send_http_header;
                    $r->print("it works");
                    return OK;
                }!);

                return OK;
            }';
        }

        location /print {
            perl 'sub {
                my $r = shift;
                $r->send_http_header;
                eval q!$r->print("it works")!;
                return OK;
            }';
        }

        location /redirect {
            perl 'sub {
                my $r = shift;
                eval q!$r->internal_redirect("/print")!;
                return OK;
            }';
        }

        location /stale {
            perl 'sub {
                my $r = shift;
                $prev->log_error(0, "next request arrived") if $prev;
                $r->send_http_header;
                $prev->print("print to stale request") if $prev;
                $prev = $r;
                return OK;
            }';
        }

        location /bless {
            perl 'sub {
                my $v = 10;
                my $r = bless \$v, "nginx";
                $r->send_http_header;
                $r->print("it works");
                return OK;
            }';
        }
    }
}

EOF

$t->run();

###############################################################################

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.3');

# $r->sleep() handler from an eval() might be freed by perl,
# and needs to be properly refcounted till it's no longer needed

like(http_get('/sleep'), qr/works/, 'perl sleep and eval');

# similarly, $r->has_request_body() handler from an eval()
# also needs to be properly refcounted

like(http(
        'GET /body HTTP/1.0' . CRLF
        . 'Host: localhost' . CRLF
        . 'Content-Length: 10' . CRLF . CRLF,
        sleep => 0.1,
        body => '1234567890'
), qr/works/, 'perl body and eval');

# similarly, even read-only strings in an eval() might be freed,
# and need to be either properly refcounted or copied

like(http_get('/print'), qr/works/, 'perl print in eval');
like(http_get('/redirect'), qr/works/, 'perl redirect in eval');

}

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.3');
todo_skip 'might coredump', 2 unless $t->has_version('1.31.3')
	or $ENV{TEST_NGINX_UNSAFE};

# the $r request object might be preserved by the code,
# and usage of such invalid request objects needs to be prevented;
# note though that the stale request might happen to match the active one

http_get('/stale');
like(http_get('/stale'), qr/500 Internal|stale request/,
	'stale request object');

# similarly, if the request object is constructed with bless()
# with an incorrect pointer, it should be rejected

like(http_get('/bless'), qr/500 Internal/, 'invalid request object');

}

###############################################################################
