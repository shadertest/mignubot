#!/usr/bin/perl -w

use warnings;
use strict;
use 5.010;
use diagnostics;

use POSIX qw(setsid);
use IO::Socket::UNIX;


use LWP;
use XML::Simple;
use URI::Escape;
use JSON;
use HTML::Entities;
use LWP::Protocol::https;

use vars qw(%options);

%options = (
    debug => 1,
    unixsocket => "socket",
);

my $ua = LWP::UserAgent->new();

my $socket = new IO::Socket::UNIX(Type => SOCK_STREAM,
                                  Peer => $options{unixsocket});

sub metar {
    my $icao = shift;
    my $response = $ua->get(
        "ftp://tgftp.nws.noaa.gov/data/observations/metar/stations/$icao.TXT");
    my $data = $response->decoded_content;
    $data =~ s/\d+\/\d+\/\d+ \d+:\d+//;
    $data =~ s/\R//g;
    return $data;
}

sub weather {
    my $city = shift;
    $city =~ s/\s/+/g;
    $city = uri_escape($city, "^A-Za-z0-9\-\._~+");
    my $response = $ua->get("http://www.google.com/ig/api?weather=$city");
    my $data = $response->decoded_content;
    my $xmldata = XMLin("$data", ValueAttr => [ 'data' ] );
    $city = $xmldata->{'weather'}{'forecast_information'}{'city'};
    my $conditions = $xmldata->{'weather'}{'current_conditions'};
    my @current = values %{$conditions};
    return "$city: $current[5] $current[2]°C/$current[1]°F $current[3] $current[4]"
        if (@current);
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
        my $channel = $1;
        if (/,me(tar)? (.+)/) {
            syswrite($socket, "PRIVMSG $channel :". &metar($2) ."\n");
        } elsif (/,we(ather)? (.+)/) {
            syswrite($socket, "PRIVMSG $channel :". &weather($2) ."\n");
        }
    }
}

