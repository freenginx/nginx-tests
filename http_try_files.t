#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for try_files directive.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(17)
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
            try_files $uri /fallback;
        }

        location /fallback {
            proxy_pass http://127.0.0.1:8081/fallback;
        }

        location /nouri/ {
            try_files $uri /fallback-nouri;
        }

        location /fallback-nouri {
            proxy_pass http://127.0.0.1:8081;
        }

        location /short/ {
            try_files /short $uri =404;
        }

        location /file-file/ {
            try_files /found.html =404;
        }

        location /file-dir/ {
            try_files /found.html/ =404;
        }

        location /dir-dir/ {
            try_files /directory/ =404;
        }

        location /dir-file/ {
            try_files /directory =404;
        }

        location ~ /alias-re.html {
            alias %%TESTDIR%%/directory;
            try_files $uri =404;
        }

        location ~ /alias-re-add/(.*) {
            alias %%TESTDIR%%/$1;
            try_files .htm .html =404;
        }

        location ~ /alias-re-prefix/(.*) {
            alias %%TESTDIR%%/$1;
            try_files $uri.htm $uri.html =404;
        }

        location /alias-nested/ {
            alias %%TESTDIR%%/;
            location ~ html {
                try_files $uri =404;
            }
        }

        location /alias-static/ {
            alias %%TESTDIR%%/;
            try_files /alias-static/found.html =404;
        }

        location /alias-vars/ {
            alias %%TESTDIR%%/;
            set $file /alias-vars/found.html;
            try_files $file =404;
        }

        location /alias-fallback-static/ {
            alias %%TESTDIR%%/;
            try_files $uri /alias-fallback-static/found.html;
        }

        location /alias-fallback-vars/ {
            alias %%TESTDIR%%/;
            set $fallback /alias-fallback-vars/found.html;
            try_files $uri $fallback;
        }

        location /alias-caseless/ {
            alias %%TESTDIR%%/;
            set $file /alias-caseless/found.html;
            try_files $file =404;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-URI $request_uri;
            return 204;
        }
    }
}

EOF

mkdir($t->testdir() . '/directory');
$t->write_file('directory/alias-re.html', 'SEE THIS');
$t->write_file('found.html', 'SEE THIS');
$t->run();

###############################################################################

like(http_get('/found.html'), qr!SEE THIS!, 'found');
like(http_get('/uri/notfound'), qr!X-URI: /fallback!, 'not found uri');
like(http_get('/nouri/notfound'), qr!X-URI: /fallback!, 'not found nouri');
like(http_get('/short/long'), qr!404 Not!, 'short uri in try_files');

like(http_get('/file-file/'), qr!SEE THIS!, 'file matches file');
like(http_get('/file-dir/'), qr!404 Not!, 'file does not match dir');
like(http_get('/dir-dir/'), qr!301 Moved Permanently!, 'dir matches dir');
like(http_get('/dir-file/'), qr!404 Not!, 'dir does not match file');

like(http_get('/alias-re.html'), qr!SEE THIS|404 Not!,
	'alias in regex location as root');
like(http_get('/alias-re-add/found'), qr!SEE THIS!,
	'alias in regex location with just extension');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.0');

like(http_get('/alias-re-prefix/found'), qr!SEE THIS!,
	'alias in regex location with uri prefix');

}

like(http_get('/alias-nested/found.html'), qr!SEE THIS!,
	'alias with nested location');

# when a file matches location prefix covered by alias,
# prefix needs to be removed; this used to work only with
# variables, but not with static strings

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.0');

like(http_get('/alias-static/found.html'), qr!SEE THIS!,
	'alias with static string');

}

like(http_get('/alias-vars/found.html'), qr!SEE THIS!,
	'alias with variables');

# in contrast, for the fallback URI we don't need to remove
# anything (yet it was removed with variables)

like(http_get('/alias-fallback-static/notfound'), qr!SEE THIS!,
	'alias fallback to matching static string');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.0');

like(http_get('/alias-fallback-vars/notfound'), qr!SEE THIS!,
	'alias fallback to matching string with variables');

}

# with caseless systems, aliased prefix needs to be checked in a
# case-insensitive way; this automatically happens with "try_files $uri",
# since aliased prefix is compared to the original request URI, but was
# not working with configuration-provided paths

SKIP: {
skip 'not caseless os', 1
	unless $^O eq 'MSWin32' or $^O eq 'darwin';
local $TODO = 'not yet' unless $t->has_version('1.31.0');

like(http_get('/alias-CASELESS/found.html'), qr!SEE THIS!, 'alias caseless');

}

###############################################################################
