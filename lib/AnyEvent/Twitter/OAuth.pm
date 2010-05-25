package AnyEvent::Twitter::OAuth;
use strict;
use warnings;
use utf8;
use Encode;
our $VERSION = '0.01';

use Carp;
use JSON;
use Net::OAuth;
use Digest::SHA;
use AnyEvent::HTTP;

$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;

sub new {
    my $class = shift;
    my %args  = @_;

    $args{consumer_key}        || Carp::croak "consumer_key is needed";
    $args{consumer_secret}     || Carp::croak "consumer_secret is needed";
    $args{access_token}        || Carp::croak "access_token is needed";
    $args{access_token_secret} || Carp::croak "access_token_secret is needed";

    bless \%args, $class;
}

sub request {
    my $self = shift;
    my $cb   = pop;
    my %opt  = @_;

    my $url;
    if ($opt{url}) {
        $url = $opt{url};
    } else {
        $opt{api} ? $url = 'http://api.twitter.com/1/' . $opt{api} . '.json'
                  : Carp::croak "'api' or 'url' option is required"
                  ;
    }

    ref($cb) eq 'CODE'              || Carp::croak "coderef argument is required";
    $opt{method} =~ /^(GET|POST)$/i || Carp::croak "'method' option is required";

    my %params;
    %params = %{$opt{params}} if ($opt{params});

    my $req = $self->_make_oauth_request(
        request_url    => $url,
        request_method => $opt{method},
        extra_params   => \%params,
    );

    my $req_url;

    my %req_params;
    if ($opt{method} =~ /POST/i) {
        $req_params{body} = $req->to_post_body;
        $req_url = $req->normalized_request_url();
    } else {
        $req_url = $req->to_url;
    }

    http_request($opt{method} => $req_url, %req_params, sub {
        my ($body, $hdr) = @_;

        if ($hdr->{Status} =~ /^2/) {
            my $json = eval { decode_json($body); };
            $@ ? $cb->($hdr, undef, $@) : $cb->($hdr, $json, $hdr->{Reason}) ;
        }
        else {
            $cb->($hdr, undef, $hdr->{Reason});
        }
    });
}

sub _make_oauth_request {
    my $self = shift;
    my %opt  = @_;

    local $Net::OAuth::SKIP_UTF8_DOUBLE_ENCODE_CHECK = 1;

    my $req = Net::OAuth->request('protected resource')->new(
        version          => '1.0',
        consumer_key     => $self->{consumer_key},
        consumer_secret  => $self->{consumer_secret},
        token            => $self->{access_token},
        token_secret     => $self->{access_token_secret},
        signature_method => 'HMAC-SHA1',
        timestamp        => time,
        nonce            => Digest::SHA::sha1_base64(time . $$ . rand),
        %opt,
    );
    $req->sign;

    $req;
}

1;
__END__

=head1 NAME

AnyEvent::Twitter::OAuth - A thin wrapper for Twitter API using OAuth

=head1 SYNOPSIS

    use utf8;
    use Data::Dumper;
    use AnyEvent;
    use AnyEvent::Twitter::OAuth;

    my $ua = AnyEvent::Twitter::OAuth->new(
        consumer_key        => 'consumer_key',
        consumer_secret     => 'consumer_secret',
        access_token        => 'access_token',
        access_token_secret => 'access_token_secret',
    );

    # if you use eg/gen_token.pl, simply as:
    #
    # use JSON;
    # use Perl6::Slurp;
    # my $json_text = slurp 'config.json';
    # my $config = decode_json($json_text);
    # my $ua = AnyEvent::Twitter::OAuth->new(%$config);

    my $cv = AE::cv;
    $ua->request(
        api    => 'account/verify_credentials',
        method => 'GET',
        sub {
            my ($hdr, $res, $reason) = @_;

            unless ($res) {
                print $reason, "\n";
            }
            else {
                print "ratelimit-remaining : ", $hdr->{'x-ratelimit-remaining'}, "\n",
                      "x-ratelimit-reset   : ", $hdr->{'x-ratelimit-reset'}, "\n",
                      "screen_name         : ", $res->{screen_name}, "\n";
            }
        }
    );
    $ua->request(
        api => 'statuses/update',
        method => 'POST',
        params => {
            status => '(#`ω´)クポー クポー',
        },
        sub {
            print Dumper \@_;
        }
    );
    $ua->request(
        url => 'http://api.twitter.com/1/statuses/update.json',
        method => 'POST',
        params => {
            status => '(#`ω´)クポー クポー',
        },
        sub {
            print Dumper \@_;
        }
    );
    $cv->recv;

=head1 DESCRIPTION

AnyEvent::Twitter::OAuth is a very thin wrapper for Twitter API using OAuth.

=head1 METHODS

=head2 new

All arguments are required.
If you don't know how to obtain these parameters, take a look at eg/gen_token.pl and run it.

=over 4

=item consumer_key

=item consumer_secret

=item access_token

=item access_token_secret

=back

=head2 request

These parameters are required.

=over 4

=item api or url

The api parameter is a shortcut option.

If you want to specify the API url, the url parameter is good for you. The format should be 'json'.

The api parameter will be internally processed as:

    $url = 'http://api.twitter.com/1/' . $opt{api} . '.json';

You can check the api option at http://apiwiki.twitter.com/Twitter-API-Documentation

=item method

Investigate the HTTP method of Twitter API that you want to use. Then specify it.

=item callback

This module is AnyEvent::http_request style, so you have to pass the coderef callback.

$hdr, $response and $reason will be returned. If something is wrong with the response, $response will be undef. So you can check the value like below.

    sub {
        my ($hdr, $res, $reason) = @_;

        unless ($res) {
            print $reason, "\n";
        }
        else {
            print $res->{screen_name}, "\n";
        }
    }

=back

=head1 AUTHOR

punytan E<lt>punytan@gmail.comE<gt>

=head1 SEE ALSO

L<AnyEvent::HTTP>, L<Net::OAuth>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
