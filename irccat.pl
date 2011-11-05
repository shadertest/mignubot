#!/usr/bin/perl -w

use warnings;
use strict;
use 5.010;
use diagnostics;

use POSIX qw(setsid mkfifo);
use IO::Socket::SSL;
use IO::Select;
use Fcntl;

use vars qw(%options);

%options = (
    debug => 1,
    fifoin => "input",
    fifoout => "output",
    server => "irc6.rizon.net:6667",
    nickname => "MiGNUBot",
    username => "MikuBot", # identd will override this
    ssl_key => "/home/shadertest/mocbat.key",
    ssl_cert => undef,
);

print "\e[32m*\e[0m Mignubot 2.0 by shadertest\n";
print "\e[32m*\e[0m Based off irccat by mut80r/Aaron\n";
print "\e[32m*\e[0m Licensed under the terms of the GNU GPL version 3\n";
print

### START INIT
print "\e[32m*\e[0m Opening input FIFO... ";
mkfifo($options{fifoin}, 0666) unless (-p $options{fifoin})
    or die "\e[31m[FAIL]\n $! ($@)\e[0m";
sysopen(my $input, $options{fifoin}, O_RDONLY | O_NONBLOCK)
    or die "\e[31m[FAIL]\n $! ($@)\e[0m";
print "\e[32m[DONE]\e[0m\n";

print "\e[32m*\e[0m Opening output FIFO... ";
mkfifo($options{fifoout}, 0666) unless (-p $options{fifoout})
    or die "\e[31m[FAIL]\n $! ($@)\e[0m";
sysopen(my $output, $options{fifoout}, O_RDWR | O_NONBLOCK)
    or die "\e[31m[FAIL]\n $! ($@)\e[0m";
print "\e[32m[DONE]\e[0m\n";

print "\e[32m*\e[0m Connecting to $options{server}... ";
my $irc;
if ($options{ssl_cert}) {
    print "SSL"; 
    $irc = new IO::Socket::SSL(Proto => 'tcp',
                                  PeerAddr => $options{server},
                                  SSL_use_cert => 1,
                                  SSL_key_file => $options{ssl_key},
                                  SSL_cert_file => $options{ssl_cert}); 
} else {
    print "No SSL";
    $irc = new IO::Socket::INET6(Proto => 'tcp',
                                    PeerAddr => $options{server});
}
die "\e[31m[FAIL]\n $! ($@)\e[0m" unless ($irc);
print "\e[32m[DONE]\e[0m\n";

print "\e[32m*\e[0m select()ing FIFOs and Socket... ";
my $select = new IO::Select($input, $output, $irc)
    or die "\e[31m[FAIL] $! ($@)\e[0m";
print "\e[32m[DONE]\e[0m\n";

unless ($options{debug}) {
    print "\e[32m*\e[0m Init finished, daemonizing...\n";
    my $pid = fork();
    exit(1) if (! defined($pid));
    exit(0) if ($pid > 0);
    open(STDIN, '<', '/dev/null');
    open(STDOUT, '>', '/dev/null');
    open(STDERR, '>', '/dev/null');
    setsid();
}
### END INIT
syswrite($irc, "USER $options{username} 8 * :Mi GNU Bot\n");
syswrite($irc, "NICK $options{nickname}\n");

until ($SIG{INT}) {
    my @socks = $select->can_read(1);
    for (@socks) {
        if (fileno($_) == fileno($input)) {
            sysread($input, my $line, 8192);
            syswrite($irc, $line);
        } elsif (fileno($_) == fileno($irc)) {
            sysread($irc, my $line, 8192);
            syswrite($irc, "PONG :$1\n") if ($line =~ /PING :([\w\.]+)/);
            syswrite($output, $line); 
        }
    }
}
