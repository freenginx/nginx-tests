#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for gunzip filter module with subrequests and proxying.

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

eval { require IO::Compress::Gzip; };
plan(skip_all => "IO::Compress::Gzip not found") if $@;

my $t = Test::Nginx->new()->has(qw/http gunzip ssi proxy/)->plan(1)
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
            proxy_pass http://127.0.0.1:8081;
            proxy_buffering off;
            proxy_read_timeout 500ms;
            postpone_output 0;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            ssi on;
            postpone_output 0;
            proxy_pass http://127.0.0.1:8082;
            proxy_buffering off;
            gunzip on;
        }

        location /in {
        }
    }
}

EOF

$t->write_file('include.html', 'include');
$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8082));

###############################################################################

# With unbuffered proxying and gunzip, data buffered by the postpone
# filter were not sent till additional data from the the upstream.
# To detect the issue, we use an additional proxy with a small read
# timeout.

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.4');

like(http_get('/'), qr/include:after/m, 'gunzip unbuffered');

}

###############################################################################

sub http_daemon {
	my ($t) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8082),
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

		use IO::Compress::Gzip qw(:flush);

		my ($out, $p1, $p2);
		my $z = IO::Compress::Gzip->new(\$out)
			or die "IO::Compress::Gzip failed\n";

		$z->print('<!--#include virtual="/include.html" -->:after');
		$z->flush(Z_SYNC_FLUSH);
		$p1 = $out;
		$out = '';

		$z->print(':final');
		$z->close();
		$p2 = $out;

		print $client
			"HTTP/1.1 200 OK" . CRLF .
			"Connection: close" . CRLF .
			"Content-Type: text/html" . CRLF .
			"Content-Encoding: gzip" . CRLF .
			CRLF .
			$p1;

		select undef, undef, undef, 1.5;

		print $client $p2;
	}
}

###############################################################################
