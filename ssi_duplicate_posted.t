#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for ssi module, extended tests to catch subrequest double post
# issue.

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

my $t = Test::Nginx->new()->has(qw/http ssi/)->plan(1)
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
            ssi on;
            proxy_pass http://127.0.0.1:8081;
        }

        location /fi {
        }

        location /se {
        }
    }
}

EOF

$t->write_file('first.html', 'first');
$t->write_file('second.html', 'second');
$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

# When a subrequest is initiated, its processing is started via posted
# requests mechanism by the ngx_http_post_request() call, and added to
# r->postponed to ensure correct output.  And if the relevant entry in
# r->postponed is reached before the first posted request is woken up,
# the subrequest will end up being posted twice.  This is normally safe
# and mostly equivalent to an additional write event, but wasn't
# expected to happen when an active subrequest was finalized without any
# postponed data or buffering.
#
# In particular, such a situation was observed with SSI and proxying:
# when an include was finalized and the main request was woken up,
# postponed main request data were not flushed as long as the size of
# busy buffers was below proxy_busy_buffers_size, and when another
# include arrived from the upstream, it was posted from
# ngx_http_post_request() and then posted again from the postpone
# filter.  With a static file as an include, this caused "header already
# sent" alerts.

like(http_get('/'), qr/firstsecond/m, 'ssi');

$t->todo_alerts() unless $t->has_version('1.31.4');

###############################################################################

sub http_daemon {
	my ($t) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		next if $headers eq '';

		my $p1 = '<!--#include virtual="/first.html" -->';
		my $p2 = '<!--#include virtual="/second.html" -->';

		print $client
			"HTTP/1.1 200 OK" . CRLF .
			"Connection: close" . CRLF .
			"Transfer-Encoding: chunked" . CRLF .
			"Content-Type: text/html" . CRLF .
			"X-Content-Encoding: gzip" . CRLF .
			CRLF .
			sprintf("%x", length $p1) . CRLF .
			$p1 . CRLF;

		select undef, undef, undef, 0.5;

		print $client
			sprintf("%x", length $p2) . CRLF .
			$p2 . CRLF .
			"0" . CRLF . CRLF;
	}
}

###############################################################################
