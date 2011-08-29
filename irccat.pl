#!/usr/bin/env perl

our $VERSION = '1.1.0';

########################################################################
#                                                                      #
#  irccat modifications by shadertest <shadertest@shadertest.ca>       #
#  TODO:                                                               #
#     - IPv6 Support with IO::Socket::INET6 <DONE>                     #
#     - Two-way communication support <DONE>                           #
#     - Multiline privmsg <Leave this to individiual servers>          #
#     - SSL Support <DONE>                                             #
#     - Getopt and pod                                                 #
#                                                                      #
########################################################################
########################################################################
#                                                                      #
# irccat - written in Perl. Inspired by RJ at last.fm (who wrote a     #
# Java version), and netcat, a UNIX utility to send arbitrary data to  #
# arbitrary Internet hosts with simple shell pipe mechanics. For       #
# patches, suggestions, comments, etc please send an e-mail with the   #
# subject 'irccat' to 'Aaron Jones <aaronmdjones@gmail.com>'.          #
# Released under the terms of the GNU General Public License v3.       #
#                                                                      #
########################################################################
########################################################################
#                                                                      #
# This section has moved to the pod section at the end of the script   #
#                                                                      #
########################################################################

########################################################################
# Don't edit anything below this line unless you know what you're doing

use POSIX qw(setsid);
use strict;
use warnings;
use diagnostics;

use IO::Select;
use IO::Socket::SSL;

use Getopt::Long;
use Pod::Usage;

  print 'This is irccat, version 1.1.0.', "\n";

my $daemonize = 1;
my $server = '';
my $verbose = '';
my $listen = '127.0.0.1:1234';
my $nickname = 'irccat';
my $username = 'irccat';
my $commandfile = '';
my $ssl = '';
my $ssl_key = '';
my $ssl_cert = '';

GetOptions(
           'daemonize|daemon!' => \$daemonize,
           'server=s' => \$server,
           'listen:s' => \$listen,
           'nick|nickname:s' => \$nickname,
           'user|username:s' => \$username,
           'commandfile:s' => \$commandfile,
           'verbose!' => \$verbose,
           'ssl!' => \$ssl,
           'ssl-key:s' => \$ssl_key,
           'ssl-cert:s' => \$ssl_cert
          );

$server = shift unless ($server);
pod2usage(2) unless ($server);

our @sendlines;
if ($commandfile) {
        open(COMMANDFILE, '<', $commandfile) or die('Unable to open command file ' . $commandfile . '!');
        @sendlines = <COMMANDFILE>;
        close(COMMANDFILE);
}

print 'Using nickname \'', $nickname, '\' and username \'', $username, '\'', "\n";
print 'Listening on TCP and UDP port ', $listen, "\n";
print 'Connecting to server ', $server, ' ...', "\n";
print "\n";

my $udpsock = new IO::Socket::INET6(Proto => 'udp', LocalAddr => $listen);
die("Unable to listen on UDP $listen: $! ($@)") unless ($udpsock);

my $tcpsock = new IO::Socket::INET6(Proto => 'tcp', LocalAddr => $listen, Listen => 1, ReuseAddr => $listen);
die("Unable to listen on TCP $listen: $! ($@)") unless ($tcpsock);

my $ircsock = $ssl ? new IO::Socket::SSL(Proto => 'tcp', PeerAddr => $server, SSL_use_cert => 1, SSL_key_file => $ssl_key, SSL_cert_file => $ssl_cert) :
  new IO::Socket::INET6(Proto => 'tcp', PeerAddr => $server);

die("Unable to connect to $server: $! ($@)") unless ($ircsock);

my $ios = new IO::Select($udpsock, $tcpsock, $ircsock);
die("Unable to select() on sockets: $! ($@)") unless ($ios);

print "Connected to server.\n";

if ($daemonize) {
        print "Daemonising...\n";

        my $pid = fork();
        exit(1) if (! defined($pid));
        exit(0) if ($pid > 0);

        open(STDIN, '<', '/dev/null');
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        setsid();
}


sub SocketBroadcast
  {
          my (@data) = @_;
          my $text = join('', @data) . "\n";
          my @sockets = $ios->can_write(0);
          for (@sockets) {
                  next if (fileno($_) == fileno($udpsock));
                  next if (fileno($_) == fileno($tcpsock));
                  next if (fileno($_) == fileno($ircsock));
                  syswrite($_, $text);
          }
  }

sub SocketSend
  {
          my (@data) = @_;
          my $text = join('', @data) . "\n";
          syswrite($ircsock, $text);
  }

sub ProcessPacket
  {
          my ($packet, $source, $extra) = @_;
          $packet =~ s/^\s+|\s+$//g;
          return 0 unless ($packet);
          print "$packet\n" if ($verbose);
          &SocketBroadcast($packet);
          if ($packet =~ m/^\:(.+?) (.+)$/) {
                  $source = $1; $packet = $2;
          }
          if ($packet =~ m/^(.+?) \:(.+)$/) {
                  $packet = $1; $extra = $2;
          }
          my ($cmdtype, @args) = split(/\s+/, $packet);
          $cmdtype = uc($cmdtype);
          &ProcessCommand($source, $cmdtype, \@args, $extra);
  }

sub ProcessCommand
  {
          my ($source, $cmdtype, $args, $extra) = @_;
          if ($cmdtype eq 'PING') {
                  &::SocketSend('PONG :', $extra);
          }
          if ($cmdtype eq '255') {
                  foreach (@::sendlines) {
                          &::SocketSend($_); sleep(1);
                  }
          }
  }

SocketSend('USER ', $username, ' 8 * :irccat');
SocketSend('NICK ', $nickname);

my $buf = '';
for (;;) {
        my @sockets = $ios->can_read(1);
        foreach my $socket (@sockets) {
                if (fileno($socket) == fileno($ircsock)) {
                        my $tmpbuf;
                        my $sysret = sysread($ircsock, $tmpbuf, 8192);
                        if (! defined($sysret)) {
                                die('Connection closed (Socket error)');
                        }
                        if (! $sysret) {
                                die('Connection reset by peer');
                        }
                        $buf .= $tmpbuf;
                        my $stridx = index($buf, "\n");
                        while ($stridx != -1) {
                                my $packet = substr($buf, 0, $stridx);
                                $buf = substr($buf, $stridx + 1);
                                $stridx = index($buf, "\n");
                                &ProcessPacket($packet);
                        }
                } elsif (fileno($socket) == fileno($udpsock)) {
                        my $readline = <$udpsock>;
                        if (uc($readline) eq 'QUIT') {
                                &SocketSend('QUIT :Received QUIT command from UDP socket');
                                exit(0);
                        }
                        if ($readline =~ m/^(.+?) (.+)$/) {
                                &SocketSend('PRIVMSG ', $1, ' :', $2);
                        }
                } elsif (fileno($socket) == fileno($tcpsock)) {
                        $ios->add($tcpsock->accept);
                } else {
                        my $tmpbuf;
                        my $sysret = sysread($socket, $tmpbuf, 8192);
                        if (! defined($sysret)) {
                                $ios->remove($socket), $socket->close();
                        }
                        if (! $sysret) {
                                $ios->remove($socket), $socket->close();
                        }
                        $buf .= $tmpbuf;
                        my $stridx = index($buf, "\n");
                        while ($stridx != -1) {
                                my $packet = substr($buf, 0, $stridx);
                                $buf = substr($buf, $stridx + 1);
                                $stridx = index($buf, "\n");
                                &SocketSend($packet);
                        }
                }
        }
}


__END__

=head1 NAME

irccat.pl - sends arbitrary data to an IRC server

=head1 SYNOPSIS

ircbot.pl [options] server:port

      -v --verbose                  Prints raw socket data
      -d --daemon --daemonize       Daemonizes after connecting to the server (default)
      --no-daemon --no-daemonize    Does not daemonize after connections

      -s --server <server>          Server to connect to in form domain.tld:6667 (required)
      -l --listen <ip:port>         Address to listen on in form (default 127.0.0.1:1234)
      --nick  --nickname <string>   Nickname to use (default irccat)
      -u --user--username  <string> Username to use (default irccat)
      -c --commandfile <file>       Sends the commands specified in the file

      --ssl                         Enables ssl support
      --ssl-key <file>              Path to key file
      --ssl-cert <file>             Path to cert file

=head1 DESCRIPTION

irccat - written in Perl. Inspired by RJ at last.fm (who wrote a
Java version), and netcat, a UNIX utility to send arbitrary data to
arbitrary Internet hosts with simple shell pipe mechanics.

When sending data to this script, the first thing you should put is
a destination that this script should send the rest of the data to.

The following example will send 'Testing. :)' to the channel #test

  echo '#test Testing. :)' | netcat -q0 -u 127.0.0.1 1234

And the following example will send 'Hello!' to the user Fred24

  echo 'Fred24 Hello!' | netcat -q0 -u 127.0.0.1 1234

Note that this script listens on a UDP port. Note also the -u given
to netcat. UDP is far simpler to implement, especially since this
script doesn't actually care where the data comes from.

This script daemonises upon successful connection to the server.
When you want the script to terminate, you can do one of these:

  Send 'QUIT' to the UDP socket.
  Kill it with SIGINT, SIGTERM or SIGKILL.
  /kill it on the IRC server.

=head1 AUTHOR

shadertest E<lt>shadertest@shadertest.caE<gt>, Aaron Jones E<lt>aaronmdjones@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 shadertest and Aaron Jones

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see E<lt>http://www.gnu.org/licenses/E<gt>.

=head1 BUGS

Cannot send multiline strings

=cut

