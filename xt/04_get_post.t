use strict;
use utf8;
use Encode;
use AnyEvent;
use AnyEvent::Twitter;
use JSON;
use Perl6::Slurp;
use Test::More;

my $json_text = slurp './xt/config.json';
my $config    = decode_json($json_text);

my $screen_name = $config->{screen_name};


my $ua = AnyEvent::Twitter->new(%$config);

my $cv = AE::cv;

$cv->begin;
$ua->request(
    api    => 'account/verify_credentials',
    method => 'GET',
    sub {
        my ($hdr, $res, $reason) = @_;

        is($res->{screen_name}, $screen_name, "account/verify_credentials");

        $cv->end;
    }
);

$cv->begin;
$ua->request(
    api => 'statuses/update',
    method => 'POST',
    params => {
        status => '(#`ω´)クポー クポー via api ' . scalar(localtime),
    },
    sub {
        my ($hdr, $res, $reason) = @_;

        is($res->{user}{screen_name}, $screen_name, "statuses/update");

        $cv->end;
    }
);

$cv->begin;
$ua->request(
    url => 'http://api.twitter.com/1/statuses/update.json',
    method => 'POST',
    params => {
        status => '(#`ω´)クポー クポー via url ' . time,
    },
    sub {
        my ($hdr, $res, $reason) = @_;

        is($res->{user}{screen_name}, $screen_name, "update.jon");

        $cv->end;
    }
);

$cv->recv;

done_testing();
