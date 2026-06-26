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

my $t = Test::Nginx->new()->has(qw/http perl/)->plan(4)
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

###############################################################################
