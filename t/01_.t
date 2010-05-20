use strict;
use Test::More;

use AnyEvent::Twitter::OAuth;

my $ua = AnyEvent::Twitter::OAuth->new(
    consumer_key        => 'consumer_key',
    consumer_secret     => 'consumer_secret',
    access_token        => 'access_token',
    access_token_secret => 'access_token_secret',
);

isa_ok $ua, 'AnyEvent::Twitter::OAuth';

done_testing;
