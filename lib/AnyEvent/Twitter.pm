package AnyEvent::Twitter;
use strict;
use warnings;
use utf8;
use 5.008;
use Encode;
our $VERSION = '0.53';

use Carp;
use JSON;
use URI;
use URI::Escape;
use Digest::SHA;
use AnyEvent::HTTP;

use Net::OAuth;
use Net::OAuth::ProtectedResourceRequest;
use Net::OAuth::RequestTokenRequest;

$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;

our %PATH = (
    site          => 'https://twitter.com/',
    request_token => 'https://api.twitter.com/oauth/request_token',
    authorize     => 'https://api.twitter.com/oauth/authorize',
    access_token  => 'https://api.twitter.com/oauth/access_token',
);

sub new {
    my ($class, %args) = @_;

    $args{access_token} ||= $args{token}
        or Carp::croak "access_token is required";

    $args{access_token_secret} ||= $args{token_secret}
        or Carp::croak "access_token_secret is required";

    defined $args{consumer_key}
        or Carp::croak "consumer_key is required";

    defined $args{consumer_secret}
        or Carp::croak "consumer_secret is required";

    return bless {
        %args,
    }, $class;
}

sub get {
    my $cb = pop;
    my ($self, $endpoint, $params) = @_;

    if (not defined $params) {
        $params = {};
    } elsif (ref $params ne 'HASH') {
        Carp::croak "parameters must be hashref.";
    }

    my $type = $endpoint =~ /^http.+\.json$/ ? 'url' : 'api';

    $self->request($type => $endpoint, method => 'GET', params => $params, $cb);

    return $self;
}

sub post {
    my ($self, $endpoint, $params, $cb) = @_;

    ref $params eq 'HASH'
        or Carp::croak "parameters must be hashref.";

    my $type = $endpoint =~ /^http.+\.json$/ ? 'url' : 'api';

    $self->request($type => $endpoint, method => 'POST', params => $params, $cb);

    return $self;
}

sub request {
    my $cb = pop;
    my ($self, %opt) = @_;

    my $url;
    if (defined $opt{url}) {
        $url = $opt{url};
    } elsif (defined $opt{api}) {
        $url = 'http://api.twitter.com/1/' . $opt{api} . '.json';
    } else {
        Carp::croak "'api' or 'url' option is required";
    }

    ref $cb eq 'CODE'
        or Carp::croak "callback coderef is required";

    $opt{method} = uc $opt{method};
    $opt{method} =~ /^(?:GET|POST)$/
        or Carp::croak "'method' option should be GET or POST";

    my $req = $self->_make_oauth_request(
        request_url    => $url,
        request_method => $opt{method},
        extra_params   => $opt{params},
    );

    my %req_params;
    if ($opt{method} eq 'POST') {
        $url = $req->normalized_request_url;
        $req_params{body} = $req->to_post_body;
    } else {
        $url = $req->to_url;
    }

    AnyEvent::HTTP::http_request $opt{method} => $url, %req_params, sub {
        my ($body, $hdr) = @_;

        if ($hdr->{Status} =~ /^2/) {
            local $@;
            my $json = eval { JSON::decode_json($body) };
            $cb->($hdr, $json, $@ ? "parse error: $@" : $hdr->{Reason}) ;
        } else {
            $cb->($hdr, undef, $hdr->{Reason});
        }
    };

    return $self;
}

sub _make_oauth_request {
    my $self = shift;
    my %opt  = @_;

    local $Net::OAuth::SKIP_UTF8_DOUBLE_ENCODE_CHECK = 1;

    my $req = Net::OAuth::ProtectedResourceRequest->new(
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

    return $req;
}

sub get_request_token {
    my ($class, %args) = @_;

    defined $args{consumer_key}
        or Carp::croak "consumer_key is required";

    defined $args{consumer_secret}
        or Carp::croak "consumer_secret is required";

    defined $args{callback_url}
        or Carp::croak "callback_url is required";

    ref $args{cb} eq 'CODE'
        or Carp::croak "cb is required";

    my $req = Net::OAuth::RequestTokenRequest->new(
        version          => '1.0',
        consumer_key     => $args{consumer_key},
        consumer_secret  => $args{consumer_secret},
        signature_method => 'HMAC-SHA1',
        timestamp        => time,
        nonce            => Digest::SHA::sha1_base64(time . $$ . rand),
        request_url      => $PATH{request_token},
        request_method   => 'GET',
        callback         => $args{callback_url},
    );
    $req->sign;

    AnyEvent::HTTP::http_request GET => $req->to_url, sub {
        my ($body, $header) = @_;
        my %token;

        for my $pair (split /&/, $body) {
            my ($key, $value) = split /=/, $pair;
            $token{$key} = URI::Escape::uri_unescape($value);
        }

        my $location = URI->new($PATH{authorize});
        $location->query_form(%token);

        $args{cb}->($location->as_string, $body, $header);
    };
}

1;
__END__

=encoding utf-8

=head1 NAME

AnyEvent::Twitter - A thin wrapper for Twitter API using OAuth

=head1 SYNOPSIS

    use utf8;
    use Data::Dumper;
    use AnyEvent;
    use AnyEvent::Twitter;

    my $ua = AnyEvent::Twitter->new(
        consumer_key        => 'consumer_key',
        consumer_secret     => 'consumer_secret',
        access_token        => 'access_token',
        access_token_secret => 'access_token_secret',
    );

    # or

    my $ua = AnyEvent::Twitter->new(
        consumer_key    => 'consumer_key',
        consumer_secret => 'consumer_secret',
        token           => 'access_token',
        token_secret    => 'access_token_secret',
    );

    # or, if you use eg/gen_token.pl, you can write simply as:

    use JSON;
    use Perl6::Slurp;
    my $json_text = slurp 'config.json';
    my $config    = decode_json($json_text);
    my $ua = AnyEvent::Twitter->new(%$config);

    my $cv = AE::cv;

    # GET request
    $cv->begin;
    $ua->get('account/verify_credentials', sub {
        my ($header, $response, $reason) = @_;

        say $response->{screen_name};
        $cv->end;
    });

    # GET request with parameters
    $cv->begin;
    $ua->get('account/verify_credentials', {
        include_entities => 1
    }, sub {
        my ($header, $response, $reason) = @_;

        say $response->{screen_name};
        $cv->end;
    });

    # POST request with parameters
    $cv->begin;
    $ua->post('statuses/update', {
        status => 'いろはにほへと ちりぬるを'
    }, sub {
        my ($header, $response, $reason) = @_;

        say $response->{user}{screen_name};
        $cv->end;
    });

    # verbose and old style
    $cv->begin;
    $ua->request(
        method => 'GET',
        api    => 'account/verify_credentials',
        sub {
            my ($hdr, $res, $reason) = @_;

            unless ($res) {
                print $reason, "\n";
            } else {
                print "ratelimit-remaining : ", $hdr->{'x-ratelimit-remaining'}, "\n",
                      "x-ratelimit-reset   : ", $hdr->{'x-ratelimit-reset'}, "\n",
                      "screen_name         : ", $res->{screen_name}, "\n";
            }
            $cv->end;
        }
    );

    $cv->begin;
    $ua->request(
        method => 'POST',
        api    => 'statuses/update',
        params => { status => 'hello world!' },
        sub {
            print Dumper \@_;
            $cv->end;
        }
    );

    $cv->begin;
    $ua->request(
        method => 'POST',
        url    => 'http://api.twitter.com/1/statuses/update.json',
        params => { status => 'いろはにほへと ちりぬるを' },
        sub {
            print Dumper \@_;
            $cv->end;
        }
    );

    $cv->recv;

=head1 DESCRIPTION

AnyEvent::Twitter is a very thin wrapper for Twitter API using OAuth.

=head1 METHODS

=head2 new

All arguments are required.
If you don't know how to obtain these parameters, take a look at eg/gen_token.pl and run it.

=over 4

=item consumer_key

=item consumer_secret

=item access_token (or token)

=item access_token_secret (or token_secret)

=back

=head2 get

=over 4

=item $ua->get($api, sub {})

=item $ua->get($api, \%params, sub {})

=item $ua->get($url, sub {})

=item $ua->get($url, \%params, sub {})

=back

=head2 post

=over 4

=item $ua->post($api, \%params, sub {})

=item $ua->post($url, \%params, sub {})

=back

=head2 request

These parameters are required.

=over 4

=item api or url

The C<api> parameter is a shortcut option.

If you want to specify the API C<url>, the C<url> parameter is good for you. The format should be 'json'.

The C<api> parameter will be internally processed as:

    $url = 'http://api.twitter.com/1/' . $opt{api} . '.json';

You can check the C<api> option at L<API Documentation|http://dev.twitter.com/doc>

=item method and params

Investigate the HTTP method and required parameters of Twitter API that you want to use.
Then specify it. GET/POST methods are allowed. You can omit C<params> if Twitter API doesn't requires option.

=item callback

This module is AnyEvent::HTTP style, so you have to pass the callback (coderef).

Passed callback will be called with C<$header>, C<$response> and C<$reason>.
If something is wrong with the response from Twitter API, C<$response> will be C<undef>. So you can check the value like below.

    sub {
        my ($header, $response, $reason) = @_;

        unless ($response) {
            print $reason, "\n";
        } else {
            print $response->{screen_name}, "\n";
        }
    }

=back

=head1 CONTRIBUTORS

=over 4

=item ramusara

He gave me plenty of test code.

=item Hideki Yamamura

He cleaned my code up.

=back

=head1 AUTHOR

punytan E<lt>punytan@gmail.comE<gt>

=head1 SEE ALSO

L<AnyEvent::HTTP>, L<Net::OAuth>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
