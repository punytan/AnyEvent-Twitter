use strict;
use Test::More tests => 1;

use AnyEvent::Twitter;

my $ua = AnyEvent::Twitter->new(
    consumer_key        => 'consumer_key',
    consumer_secret     => 'consumer_secret',
    access_token        => 'access_token',
    access_token_secret => 'access_token_secret',
);

isa_ok $ua, 'AnyEvent::Twitter';

done_testing;
