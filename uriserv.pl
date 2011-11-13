#!/usr/bin/perl -w

use warnings;
use strict;
use 5.010;
use diagnostics;

use POSIX qw(setsid);
use IO::Socket::UNIX;

use LWP::UserAgent;
use HTML::HeadParser;
use LWP::Protocol::https;

use vars qw(%options);

%options = (
    debug => 1,
    unixsocket => "socket",
);

my $ua = new LWP::UserAgent(agent => "Mozilla/5.0 (X11; Linux x86_64; rv:11.0a1) Gecko/20111111 Firefox/11.0a1");

my $socket = new IO::Socket::UNIX(Type => SOCK_STREAM,
                                  Peer => $options{unixsocket});
                                  
sub convertBytes {
    my ($bytes) = @_;
    if ($bytes > 1048576) {
        return sprintf("%.2f MiB", $bytes/1048576);
    } elsif ($bytes > 1024) {
        return sprintf("%.2f KiB", $bytes/1024);
    } else {
        return $bytes." Bytes";
    }
}

sub getTitle {
    my $uri = shift;
    $uri =~ s/(\x03(?:\d{1,2}(?:,\d{1,2})?)?|\x02|\x1f|\x0f|x16)//g;
    my $response = $ua->head($uri);
    my $type = $response->header('Content-Type');
    my $length = $response->header('Content-Length');

    if ($type =~ m/text\/html/) {
        return "\0034ERROR: File too large\003" if ($length > 6291456);
        my $p = HTML::HeadParser->new;
        $ua->max_size(10240);
        $response = $ua->get($uri);
        $p->parse($response->decoded_content);
        my $title = $p->header('Title');
        $title = $response->code && next unless ($title);
        $title =~ s/\R/ /gmi;
        return "[\0033URI\003] $title";
    }
    return undef unless($length);
    $length = convertBytes($length);
    return "[\0033URI\003] \'$type\' $length";
}

sub getTitles {
    my $channel = shift;
    for (@_) {
        s/^://;
        if (/https?:\/\//) {
            my $title = &getTitle($_);
            syswrite($socket, "PRIVMSG $channel :$title\n") if ($title);             
        }
    }  
}

unless ($options{debug}) {
    my $pid = fork();
    exit(1) if (! defined($pid));
    exit(0) if ($pid > 0);
    open(STDIN, '<', '/dev/null');
    open(STDOUT, '>', '/dev/null');
    open(STDERR, '>', '/dev/null');
    setsid();
}


until ($SIG{INT}) {
    sysread($socket, $_, 1024);
    if (/PRIVMSG (\S+)/) {
        &getTitles($1, split)
    }
}


