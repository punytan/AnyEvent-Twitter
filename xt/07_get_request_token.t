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

my $oauth_token_secret;
{
    my $cv = AE::cv;
    $cv->begin;
    AnyEvent::Twitter->get_request_token(
        consumer_key    => $config->{consumer_key},
        consumer_secret => $config->{consumer_secret},
        callback_url    => 'http://localhost:5000/',
        cb => sub {
            my $location = shift;
            note Dumper \@_;
            note $location;
            like $location, qr/^http/, 'authorize location';

            $oauth_token_secret = $location =~ /oauth_token_secret=([^&]+)/;
            $cv->end;
        },
    );
    $cv->recv;
}

{
    print "token: ";
    my $oauth_token = <STDIN>;
    chomp $oauth_token;

    print "verifier: ";
    my $oauth_verifier = <STDIN>;
    chomp $oauth_verifier;

    my $cv = AE::cv;
    $cv->begin;
    AnyEvent::Twitter->get_access_token(
        consumer_key    => $config->{consumer_key},
        consumer_secret => $config->{consumer_secret},
        oauth_token     => $oauth_token,
        oauth_token_secret => $oauth_token_secret,
        oauth_verifier  => $oauth_verifier,
        cb => sub {
            note Dumper \@_;
            $cv->end;
        },
    );
    $cv->recv;
}

done_testing();

