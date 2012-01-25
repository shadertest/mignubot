#!/usr/bin/perl -w

use warnings;
use strict;
use 5.010;
use diagnostics;

use POSIX qw(setsid);
use IO::Socket::UNIX;

use XML::Simple;
use URI::Escape;
use JSON;
use HTML::Entities;
use WWW::Curl::Easy;

my %options = do "rc.pl";
die "\e[31m[FAIL] Could not parse rc.pl: $@\n" if ($@);
die "\e[31m[FAIL] Could not open rc.pl: $!\n" unless (%options);

my $socket = new IO::Socket::UNIX(
    Type => SOCK_STREAM,
    Peer => $options{unixsocket}
);

sub metar {
    my $icao     = shift;
    my $data;
    my $curl = new WWW::Curl::Easy;
    $curl->setopt( CURLOPT_URL,
                   "ftp://tgftp.nws.noaa.gov/data/observations/metar/stations/$icao.TXT" );
    $curl->setopt( CURLOPT_WRITEDATA, \$data);
    my $retcode = $curl->perform;
    return "curl returned $retcode (" . $curl->strerror($retcode) . ")"
        unless ($retcode == 0);
    $data =~ s/\d+\/\d+\/\d+ \d+:\d+//;
    $data =~ s/\R//g;
    return $data;
}

sub weather {
    my $city = shift;
    $city =~ s/\s/+/g;
    $city = uri_escape( $city, "^A-Za-z0-9\-\._~+" );
    my $data;
    my $curl = new WWW::Curl::Easy;
    $curl->setopt( CURLOPT_URL,
                   "http://www.google.com/ig/api?weather=$city" );
    $curl->setopt( CURLOPT_WRITEDATA, \$data);
    my $retcode = $curl->perform;
    return "curl returned $retcode (" . $curl->strerror($retcode) . ")"
        unless ($retcode == 0);
    my $xmldata  = XMLin( "$data", ValueAttr => ['data'] );
    $city = $xmldata->{'weather'}{'forecast_information'}{'city'};
    my $conditions = $xmldata->{'weather'}{'current_conditions'};
    my @current    = values %{$conditions};
    return
      "$city: $current[5] $current[2]°C/$current[1]°F $current[3] $current[4]"
    if (@current);
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
        my $channel = $1;
        if (/,me (\w+)/) {
            syswrite( $socket, "PRIVMSG $channel :" . &metar($1) . "\n" );
        }
        elsif (/,w[ex] (.+)/) {
            syswrite( $socket, "PRIVMSG $channel :" . &weather($1) . "\n" );
        }
    }
}

