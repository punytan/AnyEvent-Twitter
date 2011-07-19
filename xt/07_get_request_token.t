use strict;
use utf8;
use Test::More;

use Data::Dumper;
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

my $cv = AE::cv;
$cv->begin;
AnyEvent::Twitter->get_request_token(
    consumer_key    => $config->{consumer_key},
    consumer_secret => $config->{consumer_secret},
    callback_url    => 'http://localhost:5000/',
    cb => sub {
        like shift, qr/^http/, 'authorize location';
        $cv->end;
    },
);

$cv->recv;

done_testing();
