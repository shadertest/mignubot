#!/usr/bin/perl -w

use warnings;
use strict;
use 5.010;
use diagnostics;

use POSIX qw(setsid);
use LWP;
use XML::Simple;
use URI::Escape;
use JSON;
use HTML::Entities;
use Fcntl;
use IO::Select;
use LWP::Protocol::https;

use vars qw(%options);

%options = (
    debug => 1,
    fifoout => "input",
    fifoin => "output"
);

my $ua = LWP::UserAgent->new();

sysopen(my $input, $options{fifoin}, O_RDONLY | O_NONBLOCK)
    or die "\e[31m[FAIL]\n $! ($@)\e[0m";
sysopen(my $output, $options{fifoout}, O_RDWR | O_NONBLOCK)
    or die "\e[31m[FAIL]\n $! ($@)\e[0m";
my $select = new IO::Select($input, $output);

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

sub translate {
    ##########
    # WILL NOT BE FUNCTIONAL COME 01/12/2011
    ##########
    my ($source, $target, $text) = @_;
    $text = uri_escape($text);
    my $response = $ua->get(
        "https://www.googleapis.com/language/translate/v2?key=AIzaSyAzwvM58m2a-iWcvVdwPkpuMRiYI9Mv6-k&q=$text&source=$source&target=$target");
    my $data = $response->decoded_content;
    my $json_data = decode_json($data);
    my $translated = $json_data->{'data'}{'translations'}[0]{'translatedText'};
    $translated = decode_entities($translated);
    return "[$source=>$target] $translated";
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
    my @files = $select->can_read(1);
    for (@files) {
        if (fileno($_) == fileno($input)) {
            sysread($input, $_, 8192);
            if (/PRIVMSG (\S+)/) {
                my $channel = $1;
                if (/,me(tar)? (.+)/) {
                    syswrite($output, "PRIVMSG $channel :". &metar($2) ."\n");
                } elsif (/,we(ather)? (.+)/) {
                    syswrite($output, "PRIVMSG $channel :". &weather($2) ."\n");
                } elsif (/,tr(anslate)? (\w\w)( |\|)(\w\w) (.+)/) {
                    syswrite($output, "PRIVMSG $channel :". &translate($2, $4, $5) ."\n");
                }
            }
        }
    }
}


