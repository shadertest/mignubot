#!/usr/bin/env perl

# miscserv.pl - misc. functions for MiGNUBot
# Copyright (C) 2011-2012 shadertest <shadertest@shadertest.ca>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use warnings;
use strict;
use 5.010;
use diagnostics;

use POSIX qw(setsid);
use IO::Socket::UNIX;

use XML::Simple;
use URI::Escape;
use WWW::Curl::Easy;

my %options = do "rc.pl"
  or die "Could not open rc.pl: $!";
die "Could not parse rc.pl: $@\n" if ($@);

my $socket = new IO::Socket::UNIX(
    Type => SOCK_STREAM,
    Peer => $options{unixsocket}
) or die "Could not connect to UNIX socket: $! ($@)";

sub metar {

    # Get the METAR for the airport $icao
    my $icao = shift;
    my $data;
    my $curl = new WWW::Curl::Easy;
    $curl->setopt( CURLOPT_URL,
        "ftp://tgftp.nws.noaa.gov/data/observations/metar/stations/$icao.TXT" );
    $curl->setopt( CURLOPT_WRITEDATA, \$data );
    my $retcode = $curl->perform;
    return "curl returned $retcode (" . $curl->strerror($retcode) . ")"
      unless ( $retcode == 0 );
    my @data = split( /\n/, $data );
    return $data[1];
}

sub weather {

    # Get the weather for $city
    my $city = shift;
    $city =~ s/\s/+/g;
    $city = uri_escape( $city, "^A-Za-z0-9\-\._~+" );
    my $data;
    my $curl = new WWW::Curl::Easy;
    $curl->setopt( CURLOPT_URL, "http://www.google.com/ig/api?weather=$city" );
    $curl->setopt( CURLOPT_WRITEDATA, \$data );
    my $retcode = $curl->perform;
    return "curl returned $retcode (" . $curl->strerror($retcode) . ")"
      unless ( $retcode == 0 );
    my $xmldata = XMLin( "$data", ValueAttr => ['data'] );
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

    # Main loop: get PRIVMSGs and handle appropiately
    my $read = sysread( $socket, $_, 1024 )
      or die;
    die unless ( defined $read );
    if (/:\S+ PRIVMSG (.+) :(.+)/) {
        my $channel = $1;
        my $output;
        given ($2) {
            when (/^,me ([A-Z]{4})/) { $output = &metar($1); }
            when (/^,w[ex] (.+)/)    { $output = &weather($1); }
        }
        syswrite( $socket, "PRIVMSG $channel :$output\n" ) if ($output);
    }
}

