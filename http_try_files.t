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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite map/)->plan(49)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $uri $map_capture {
       ~(?<capture>.*) $capture;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            try_files $uri $uri.html $uri/ =404;
        }

        location /alias/ {
            alias %%TESTDIR%%/;
            try_files $uri $uri.html $uri/ =404;
        }

        location ~ /alias-re-add/(.*) {
            alias %%TESTDIR%%/$1;
            try_files "" .html / =404;
        }

        location ~ /alias-re-prefix/(.*) {
            alias %%TESTDIR%%/$1;
            try_files $uri $uri.html $uri/ =404;
        }

        location /uri/ {
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

        location /alias-nested/ {
            alias %%TESTDIR%%/;

            location ~ html {
                try_files $uri =404;
            }

            location /alias-nested/prefix {
                try_files /found.html =404;
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

        location /prefix-proxy/ {
            try_files $uri =404;
            proxy_pass http://127.0.0.1:8081/changed/;
        }

        location /prefix-proxy-alias/ {
            alias %%TESTDIR%%/;
            try_files $uri =404;
            proxy_pass http://127.0.0.1:8081/changed/;

            location /prefix-proxy-alias/nested-short {
                try_files /prefix-proxy-alias/nested =404;
                proxy_pass http://127.0.0.1:8081/changed/;
            }
        }

        location /prefix-proxy-long/ {
            try_files /prefix-proxy/found.html =404;
            proxy_pass http://127.0.0.1:8081/changed/;
        }

        location /prefix-proxy-short/ {
            try_files /found.html =404;
            proxy_pass http://127.0.0.1:8081/changed/;
        }

        location /uri-after/ {
            rewrite ^/uri-after/rewrite /uri-after/notfound break;
            try_files /uri-after/found.html =404;
            proxy_pass http://127.0.0.1:8081;
        }

        location /uri-after-alias/ {
            alias %%TESTDIR%%/;
            try_files /uri-after-alias/found.html =404;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /uri-after-alias-redirect {
            try_files /notfound /uri-after-alias/found;
        }

        location ~ /uri-after-alias-add/(.*) {
            alias %%TESTDIR%%/$1;
            try_files .htm .html =404;
            proxy_pass http://127.0.0.1:8081;
        }

        location = /uri-after-alias-add-redirect {
            try_files /notfound /uri-after-alias-add/found;
        }

        location /map/ {
            try_files /$capture/$map_capture =404;
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

$t->write_file('found.html', 'SEE THIS');
$t->write_file('nested', 'SEE THIS');
mkdir($t->testdir() . '/directory');
$t->write_file('directory/alias-re.html', 'SEE THIS');
$t->write_file('directory/index.html', 'SEE THIS');
mkdir($t->testdir() . '/prefix-proxy/');
$t->write_file('prefix-proxy/found.html', 'SEE THIS');
mkdir($t->testdir() . '/uri-after/');
$t->write_file('uri-after/found.html', 'SEE THIS');
$t->run();

###############################################################################

# basic tests with "try_files $uri $uri.html $uri/ =404"

like(http_get('/found.html'), qr!SEE THIS!, 'root $uri');
like(http_get('/found'), qr!SEE THIS!, 'root $uri.html');
like(http_get('/directory'), qr!301 Moved Permanently!, 'root $uri/ redirect');
like(http_get('/directory/'), qr!SEE THIS!, 'root $uri/ index');
like(http_get('/notfound'), qr!404 Not!, 'root not found');

like(http_get('/alias/found.html'), qr!SEE THIS!, 'alias $uri');
like(http_get('/alias/found'), qr!SEE THIS!, 'alias $uri.html');
like(http_get('/alias/directory'), qr!301 Moved Permanently!,
	'alias $uri/ redirect');
like(http_get('/alias/directory/'), qr!SEE THIS!, 'alias $uri/ index');
like(http_get('/alias/notfound'), qr!404 Not!, 'alias not found');

like(http_get('/alias-re-add/found.html'), qr!SEE THIS!, 'alias regex ""');
like(http_get('/alias-re-add/found'), qr!SEE THIS!, 'alias regex .html');
like(http_get('/alias-re-add/directory'), qr!301 Moved Permanently!,
	'alias regex / redirect');
like(http_get('/alias-re-add/directory/'), qr!SEE THIS!,
	'alias regex / index');
like(http_get('/alias-re-add/notfound'), qr!404 Not!, 'alias regex not found');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.0');

like(http_get('/alias-re-prefix/found.html'), qr!SEE THIS!,
	'alias regex $uri');
like(http_get('/alias-re-prefix/found'), qr!SEE THIS!,
	'alias regex $uri.html');
like(http_get('/alias-re-prefix/directory'), qr!301 Moved Permanently!,
	'alias regex $uri/ redirect');
like(http_get('/alias-re-prefix/directory/'), qr!SEE THIS!,
	'alias regex $uri/ index');

}

like(http_get('/alias-re-prefix/notfound'), qr!404 Not!,
	'alias regex not found with prefix');

# various specific tests

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
	'alias with nested regex location');
like(http_get('/alias-nested/prefix'), qr!SEE THIS!,
	'alias with nested prefix location');

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

# when an URI is changed by try_files, this could be a surprise
# for proxy_pass with URI part

like(http_get('/prefix-proxy/found.html'), qr!X-URI: /changed/found.html!,
	'proxy after try_files');
like(http_get('/prefix-proxy-alias/found.html'),
	qr!X-URI: /changed/found.html!, 'proxy after try_files with alias');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.0');

like(http_get('/prefix-proxy-long/found.html'),
	qr!X-URI: /prefix-proxy/found.html!, 'proxy after try_files no match');

}

TODO: {
todo_skip 'leaves coredump', 2
	unless $t->has_version('1.31.0') or $ENV{TEST_NGINX_UNSAFE};
local $TODO = 'not yet', $t->todo_alerts()
	unless $t->has_version('1.31.0');

like(http_get('/prefix-proxy-short/foo'), qr!X-URI: /found.html!,
	'proxy after try_files with short uri');
like(http_get('/prefix-proxy-alias/nested-short'),
	qr!X-URI: /prefix-proxy-alias/nested!,
	'proxy after try_files with short uri, alias nested');

}

# try_files changes URI, so make sure that proxy_pass without the URI part
# uses the modified URI, and not the original unparsed URI

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.0');

like(http_get('/uri-after/found'), qr!X-URI: /uri-after/found.html!,
	'proxy without uri, unparsed uri not used');

}

like(http_get('/uri-after/rewrite'), qr!X-URI: /uri-after/found.html!,
	'proxy without uri, after rewrite');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.0');

like(http_get('/uri-after-alias/found'),
	qr!X-URI: /uri-after-alias/found.html!,
	'proxy without uri, alias');

like(http_get('/uri-after-alias-redirect'),
	qr!X-URI: /uri-after-alias/found.html!,
	'proxy without uri, alias, after redirect');

}

# when try_files adds an extension in a regex location with alias,
# this used to result in bogus URI (".html") and the r->add_uri_to_alias
# flag set; this was handled by ngx_http_map_uri_to_alias() and worked for
# static files, but produced unexpected results when proxying

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.0');

like(http_get('/uri-after-alias-add/found'),
	qr!X-URI: /uri-after-alias-add/found.html!,
	'proxy without uri, alias in regex location');

like(http_get('/uri-after-alias-add-redirect'),
	qr!X-URI: /uri-after-alias-add/found.html!,
	'proxy without uri, alias in regex location, after redirect');

}

TODO: {
todo_skip 'might coredump', 1
	unless $t->has_version('1.31.3')
	or $ENV{TEST_NGINX_UNSAFE};
local $TODO = 'not yet', $t->todo_alerts();

like(http_get('/map/test-long-uri'), qr!404 Not!,
	'try_files and map with side effects');

}

###############################################################################
