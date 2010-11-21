use strict;
use utf8;
use Test::More;

use JSON;
use Encode;
use AnyEvent::Twitter;

my $config;

if (-f './xt/config.json') {
    open my $fh, '<', './xt/config.json' or die $!;
    $config = decode_json(join '', <$fh>);
    close $fh or die $!;
} else {
    plan skip_all => 'There is no setting file for testing';
}

my $screen_name = $config->{screen_name};

my $ua = AnyEvent::Twitter->new(
    token           => $config->{access_token},
    token_secret    => $config->{access_token_secret},
    consumer_key    => $config->{consumer_key},
    consumer_secret => $config->{consumer_secret},
);

my $cv = AE::cv;

$cv->begin;
$ua->post('statuses/update', { status => 'いろはにほへと ' . time }, sub {
    my ($hdr, $res, $reason) = @_;

    is($res->{user}{screen_name}, $screen_name, "account/verify_credentials");
    $cv->end;
});

$cv->begin;
$ua->post('http://api.twitter.com/1/statuses/update.json', { status => 'いろはにほへと ' . time },
    sub {
        my ($hdr, $res, $reason) = @_;

        is($res->{user}{screen_name}, $screen_name, "account/verify_credentials");
        $cv->end;
    }
);

$cv->recv;

done_testing();

