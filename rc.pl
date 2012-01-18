use warnings;
use strict;
use 5.010;

return (
    debug      => 1,
    unixsocket => "socket",
    server     => "irc.rizon.net:6697",
    nickname   => "MiGNUBot",
    username   => "MikuBot",
    ssl_key    => undef,
    ssl_cert   => undef,
);

