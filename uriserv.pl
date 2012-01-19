#!/usr/bin/perl -w

use warnings;
use strict;
use 5.010;
use diagnostics;

use POSIX qw(setsid);
use IO::Socket::UNIX;
use Encode;

use HTML::HeadParser;
use WWW::Curl::Easy;

my %options = do "rc.pl";
die "\e[31m[FAIL] Could not parse rc.pl: $@\n" if ($@);
die "\e[31m[FAIL] Could not open rc.pl: $!\n" unless (%options);

my $socket = new IO::Socket::UNIX(
    Type => SOCK_STREAM,
    Peer => $options{unixsocket}
);

sub convertBytes {
    my ($bytes) = @_;
    if ( $bytes > 1048576 ) {
        return sprintf( "%.2f MiB", $bytes / 1048576 );
    }
    elsif ( $bytes > 1024 ) {
        return sprintf( "%.2f KiB", $bytes / 1024 );
    }
    else {
        return $bytes . " Bytes";
    }
}

sub getTitle {
    my $uri = shift;
    $uri =~ s/(\x03(?:\d{1,2}(?:,\d{1,2})?)?|\x02|\x1f|\x0f|\x16)//g;
    my $curl = new WWW::Curl::Easy;

    $curl->setopt( CURLOPT_USERAGENT,
"Mozilla/5.0 (X11; Linux x86_64; rv:12.0a1) Gecko/20120117 Firefox/12.0a1"
    );
    $curl->setopt( CURLOPT_NOBODY,         1 );   # We want to do a HEAD request
    $curl->setopt( CURLOPT_FOLLOWLOCATION, 1 );   # follow redirects
    $curl->setopt( CURLOPT_MAXREDIRS,      6 );   # but only 6 of them
    $curl->setopt( CURLOPT_URL,            $uri );    # pass the actual URI
    $curl->setopt( CURLOPT_SSL_VERIFYPEER, 0 );       # allow self-signed,
    $curl->setopt( CURLOPT_SSL_VERIFYHOST, 0 );       # expired, bad certs
    my $retcode = $curl->perform;
    return if ( $retcode == 6 );

    return "curl returned $retcode (" . $curl->strerror($retcode) . ")"
      unless ( $retcode == 0 or $retcode == 6 );
    my $type = $curl->getinfo(CURLINFO_CONTENT_TYPE);
    my $size = $curl->getinfo(CURLINFO_CONTENT_LENGTH_DOWNLOAD);

    if ( $type =~ m/text\/html/ and $size < 6291456 ) {
        my $body;
        $curl->setopt( CURLOPT_HTTPGET,   1 );        # now we GET
        $curl->setopt( CURLOPT_WRITEDATA, \$body );
        $retcode = $curl->perform;
        return "curl returned $retcode (" . $curl->strerror($retcode) . ")"
          unless ( $retcode == 0 or $retcode == 6 );
        my $parser = new HTML::HeadParser;
        $parser->parse($body);
        my $title = $parser->header('Title');
        $title =~ s/\R/ /gmi;
        return "[\0033URI\003] $title";
    }

    # return undef unless ($length);
    $size = convertBytes($size);
    return "[\0033URI\003] \'$type\' $size";
}

sub getTitles {
    my $channel = shift;
    for (@_) {
        s/^://;
        if (/https?:\/\//) {
            my $title = &getTitle($_);
            $title = encode( "utf8", $title );
            syswrite( $socket, "PRIVMSG $channel :$title\n" ) if ($title);
        }
    }
}

unless ( $options{debug} ) {
    my $pid = fork();
    exit(1) if ( !defined($pid) );
    exit(0) if ( $pid > 0 );
    open( STDIN,  '<', '/dev/null' );
    open( STDOUT, '>', '/dev/null' );
    open( STDERR, '>', '/dev/null' );
    setsid();
}

until ( $SIG{INT} ) {
    my $read = sysread( $socket, $_, 1024 );
    die unless ( defined $read );
    die unless ($read);
    if (/PRIVMSG (\S+)/) {
        &getTitles( $1, split );
    }
}

