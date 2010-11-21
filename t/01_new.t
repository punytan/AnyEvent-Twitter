use strict;
use Test::More;

use AnyEvent::Twitter;

my $ua = AnyEvent::Twitter->new(
    consumer_key        => 'consumer_key',
    consumer_secret     => 'consumer_secret',
    access_token        => 'access_token',
    access_token_secret => 'access_token_secret',
);

isa_ok $ua, 'AnyEvent::Twitter';

my $twitty = AnyEvent::Twitter->new(
    consumer_key    => 'consumer_key',
    consumer_secret => 'consumer_secret',
    token           => 'token',
    token_secret    => 'token_secret',
);

isa_ok $twitty, 'AnyEvent::Twitter';

done_testing;

