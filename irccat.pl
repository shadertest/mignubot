#!/usr/bin/env perl

# irccat.pl - the core script of MiGNUBot
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

# It's a good idea to have a copy of RFC 1459 while reading this

use warnings;
use strict;
use 5.010;
use diagnostics;

use POSIX qw(setsid);
use IO::Socket::UNIX;
use IO::Select;

use IO::Socket::SSL;



print "\e[32m*\e[0m MiGNUBot by shadertest\n";
print "\e[32m*\e[0m Based off irccat by mut80r/Aaron\n";
print "\e[32m*\e[0m Licensed under the terms of the GNU AGPL version 3\n";

### START INIT
# Read the options file and parse (do) it
my %options = do "rc.pl"
  or die "Could not open rc.pl: $!";
die "Could not parse rc.pl: $@\n" if ($@);

# Delete the old UNIX socket if nessecary and create a new one
unlink $options{unixsocket} if ( -e $options{unixsocket} );
my $socket = new IO::Socket::UNIX(
    Type   => SOCK_STREAM,
    Local  => $options{unixsocket},
    Listen => 1
) or die "Could not create local UNIX socket: $! ($@)";

# Connect to the IRC server over TLS (plaintext not supported)
my $irc = new IO::Socket::SSL(
    Proto         => 'tcp',
    PeerAddr      => $options{server},
    SSL_use_cert  => defined $options{ssl_cert},
    SSL_key_file  => $options{ssl_key},
    SSL_cert_file => $options{ssl_cert}
) or die "Could not create IRC Socket: $! ($@)";

# Create an object to the select() system call
my $select = new IO::Select( $socket, $irc )
  or die "Could not create IO::Select object: $! ($@)";

# Daemonize if not in debug mode
unless ( $options{debug} ) {
    my $pid = fork();
    exit(1) if ( !defined($pid) );
    exit(0) if ( $pid > 0 );
    open( STDIN,  '<', '/dev/null' );
    open( STDOUT, '>', '/dev/null' );
    open( STDERR, '>', '/dev/null' );
    setsid();
}
### END INIT

# Send the USER and NICK commands
syswrite( $irc, "USER $options{username} 8 * :MiGNUBot\n" );
syswrite( $irc, "NICK $options{nickname}\n" );

sub broadcast {

    # Send $line to all other sockets
    my $line  = shift;
    my @socks = $select->can_write(1);
    for (@socks) {
        next if ( fileno($_) == fileno($irc) );
        syswrite( $_, $line );
    }
}

until ( $SIG{INT} ) {
    # Main loop, read from all available sockets and respond
    for ( $select->can_read() ) {
        if ( fileno($_) == fileno($socket) ) {

            # A new connection was made
            my $new = $socket->accept;
            $select->add($new);
        }
        elsif ( fileno($_) == fileno($irc) ) {

            # IRC connection checks for certain requests and
            # broadcasts itself to all other connections
            my $read = sysread( $irc, my $line, 1024 )
              or die "An error occurred: $! ($@)";
            die "An error occurred: $! ($@)" unless ( defined $read );
            given ($line) {

                # Respond to PING from the server
                when (/^PING :([\w\.]+)/) { syswrite( $irc, "PONG :$1\n" ); }

                # Respond to CTCP VERSION requests
                when (/^:(.+)!.+PRIVMSG.+:\001VERSION\001/) {
                    syswrite( $irc,
                        "NOTICE $1 :\001VERSION irccat 9999 GNU/Linux\001\n" );
                }

                # Respond to source request to fufil AGPL
                when (/^:\S+ PRIVMSG (\S+) :,src/) {
                    syswrite( $irc,
"PRIVMSG $1 :Source: https://github.com/shadertest/mignubot"
                    );
                }
            }
            broadcast($line);
        }
        else {

            # Any other connection is forwared to IRC
            my $read = sysread( $_, my $line, 1024 )
              or $select->remove($_);
            $select->remove($_) unless ( defined $read );
            syswrite( $irc, $line );
        }
    }
}
