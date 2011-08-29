#!/usr/bin/perl -w
# inetserv.pl --- weather/translation retrieving server
# Author:  <shadertest@shadertest.ca>
# Created: 14 Aug 2011
# Version: 0.01

use POSIX qw(setsid);
use warnings;
use strict;

use IO::Socket::IP;
use Getopt::Long;
use Pod::Usage;
use LWP;
use XML::Simple;
use URI::Escape;
use JSON;
use HTML::Entities;

my $server = '';
my $daemonize = 1;

GetOptions(
           'daemon|daemonize!' => \$daemonize,
           'server=s' => \$server,
          );
$server = shift unless ($server);
pod2usage(2) unless ($server);

my $socket = new IO::Socket::IP(Proto => 'tcp', PeerAddr => $server) or die("Cannot open socket: $! ($@)");

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
                if (/,me(tar)? (.+)/) {
                        my $ua = LWP::UserAgent->new();
                        my $response = $ua->get("ftp://tgftp.nws.noaa.gov/data/observations/metar/stations/$2.TXT");
                        my $data = $response->decoded_content;
                        $data =~ s/\d+\/\d+\/\d+ \d+:\d+//;
                        $data =~ s/\R//g;
                        print $socket "PRIVMSG $channel :$data\n";
                } elsif (/,we(ather)? (.+)/) {
                        my $city = $2;
                        $city =~ s/\s/+/g;
                        $city = uri_escape($city, "^A-Za-z0-9\-\._~+");
                        my $ua = LWP::UserAgent->new();
                        my $response = $ua->get("http://www.google.com/ig/api?weather=$city");
                        my $data = $response->decoded_content;
                        my $xmldata = XMLin("$data", ValueAttr => [ 'data' ] );
                        $city = $xmldata->{'weather'}{'forecast_information'}{'city'};
                        my $conditions = $xmldata->{'weather'}{'current_conditions'};
                        my @current = values %{$conditions};
                        print $socket "PRIVMSG $channel :$city: $current[5] $current[2]°C/$current[1]°F $current[3] $current[4]\n" if (@current);
                } elsif (/,tr(anslate)? (\w\w)( |\|)(\w\w) (.+)/) {
                        my $text = uri_escape($5);
                        my $ua = LWP::UserAgent->new();
                        my $response = $ua->get("https://www.googleapis.com/language/translate/v2?key=AIzaSyAzwvM58m2a-iWcvVdwPkpuMRiYI9Mv6-k&q=$text&source=$2&target=$4");
                        my $data = $response->decoded_content;
                        my $json_data = decode_json($data);
                        print $socket "PRIVMSG $channel :[\0034E\003]Translation Failed\n" && next unless ($json_data->{'data'});
                        my $translated = $json_data->{'data'}{'translations'}[0]{'translatedText'};
                        $translated = decode_entities($translated);
                        print $socket "PRIVMSG $channel :[$2=>$4] $translated\n";
                }
        }
}


__END__

=head1 NAME

inetserv.pl - Describe the usage of script briefly

=head1 SYNOPSIS

inetserv.pl [options] host:port

      -d --daemon --daemonize    runs the script as a daemon after connecting
      --no-daemon --no-daemonize does the opposite
      -s --server                server in form host:port

=head1 DESCRIPTION

Stub documentation for inetserv.pl, 

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
