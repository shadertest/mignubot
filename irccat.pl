#!/usr/bin/perl -w

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
print "\e[32m*\e[0m Licensed under the terms of the GNU GPL version 3\n";

### START INIT
print "\e[32m*\e[0m Loading config file... ";
my %options = do "rc.pl";
die "\e[31m[FAIL] Could not parse rc.pl: $@\n" if ($@);
die "\e[31m[FAIL] Could not open rc.pl: $!\n" unless (%options);
print "\e[32m[DONE]\e[0m\n";

print "\e[32m*\e[0m Opening UNIX Socket... ";
unlink $options{unixsocket} if ( -e $options{unixsocket} );
my $socket = new IO::Socket::UNIX(
    Type   => SOCK_STREAM,
    Local  => $options{unixsocket},
    Listen => 1
);
print "\e[32m[DONE]\e[0m\n";

print "\e[32m*\e[0m Connecting to $options{server}... ";
my $irc = new IO::Socket::SSL(
    Proto         => 'tcp',
    PeerAddr      => $options{server},
    SSL_use_cert  => defined $options{ssl_cert},
    SSL_key_file  => $options{ssl_key},
    SSL_cert_file => $options{ssl_cert}
);
die "\e[31m[FAIL]\n $! ($@)\e[0m" unless ($irc);
print "\e[32m[DONE]\e[0m\n";

print "\e[32m*\e[0m selecting sockets... ";
my $select = new IO::Select( $socket, $irc )
  or die "\e[31m[FAIL] $! ($@)\e[0m";
print "\e[32m[DONE]\e[0m\n";

unless ( $options{debug} ) {
    print "\e[32m*\e[0m Init finished, daemonizing...\n";
    my $pid = fork();
    exit(1) if ( !defined($pid) );
    exit(0) if ( $pid > 0 );
    open( STDIN,  '<', '/dev/null' );
    open( STDOUT, '>', '/dev/null' );
    open( STDERR, '>', '/dev/null' );
    setsid();
}
### END INIT
syswrite( $irc, "USER $options{username} 8 * :MiGNUBot\n" );
syswrite( $irc, "NICK $options{nickname}\n" );

sub broadcast {
    my $line  = shift;
    my @socks = $select->can_write(1);
    for (@socks) {
        next if ( fileno($_) == fileno($irc) );
        syswrite( $_, $line );
    }
}

until ( $SIG{INT} ) {
    for ( $select->can_read() ) {
        if ( fileno($_) == fileno($socket) ) {
            my $new = $socket->accept;
            $select->add($new);
        }
        elsif ( fileno($_) == fileno($irc) ) {
            my $read = sysread( $irc, my $line, 1024 );
            die "$! ($@)" unless ( defined $read );
            die "$! ($@)" unless ($read);
            syswrite( $irc, "PONG :$1\n" ) if ( $line =~ /PING :([\w\.]+)/ );
            syswrite( $irc,
"NOTICE $1 :\001VERSION irccat 9999 GNU/Linux || Source:  https://github.com/shadertest/mignubot\001\n"
            ) if ( $line =~ /:(.+)!.+PRIVMSG.+:\001VERSION\001/ );

            broadcast($line);
        }
        else {
            my $read = sysread( $_, my $line, 1024 );
            $select->remove($_) unless ( defined $read );
            $select->remove($_) unless ($read);
            syswrite( $irc, $line );
        }
    }
}
