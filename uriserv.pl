#!/usr/bin/perl -w
# uriserv.pl --- uri title retrieving server
# Author:  <shadertest@shadertest.ca>
# Created: 14 Aug 2011
# Version: 0.01

use POSIX qw(setsid);
use warnings;
use strict;

use IO::Socket::IP;
use Getopt::Long;
use Pod::Usage;
use LWP::UserAgent;
use HTML::HeadParser;

my $server = '';
my $daemonize = 1;

GetOptions(
           'daemon|daemonize!' => \$daemonize,
           'server=s' => \$server,
          );
$server = shift unless ($server);
pod2usage(2) unless ($server);

my $socket = new IO::Socket::IP(Proto => 'tcp', PeerAddr => $server) or die("Cannot open socket: $! ($@)");

sub ConvertBytes {
        my ($bytes) = @_;
        if ($bytes > 1048576) {
                return sprintf("%.2f MiB", $bytes/1048576);
        } elsif ($bytes > 1024) {
                return sprintf("%.2f KiB", $bytes/1024);
        } else {
                return $bytes." Bytes";
        }
}

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


while (<$socket>) {
        if (/PRIVMSG (\S+)/) {
                my $channel = $1;
                for (split) {
                        s/^://;
                        if (/https?:\/\//) {
                                print $_."\n";
                                s/(\x03(?:\d{1,2}(?:,\d{1,2})?)?|\x02|\x1f|\x0f|x16)//g;
                                my $ua = new LWP::UserAgent(agent => "Mozilla/5.0 (Perl; Linux x86_64; rv:1.7) Gecko/20110808 IRCNeko/1.7");
                                my $response = $ua->head("$_");
                                my $type = $response->header('Content-Type');
                                my $length = $response->header('Content-Length');

                                if ($type =~ m/text\/html/) {
                                        next if ($length > 6291456);
                                        my $p = HTML::HeadParser->new;
                                        $response = $ua->get("$_");
                                        $p->parse($response->decoded_content);
                                        my $title = $p->header('Title');
                                        $title = $response->code && next unless ($title);
                                        $title =~ s/\R/ /gmi;
                                        print $socket "PRIVMSG $channel :[\0033URI\003] $title\n";
                                        next;
                                }
                                next unless($length);
                                $length = ConvertBytes($length);
                                print $socket "PRIVMSG $channel :[\0033URI\003] \'$type\' $length\n";
                                
                        }
                }
        }
}


__END__

=head1 NAME

uriserv.pl - Describe the usage of script briefly

=head1 SYNOPSIS

uriserv.pl [options] host:port

      -d --daemon --daemonize    runs the script as a daemon after connecting
      --no-daemon --no-daemonize does the opposite
      -s --server                server in form host:port

=head1 DESCRIPTION

Stub documentation for uriserv.pl, 

=head1 AUTHOR

E<lt>shadertest@shadertest.caE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 shadertest

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
  
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 BUGS

None reported... yet.

=cut
