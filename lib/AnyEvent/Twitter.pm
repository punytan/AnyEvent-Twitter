package AnyEvent::Twitter;
use strict;
use warnings;
use utf8;
use 5.008;
our $VERSION = '0.62';

use Carp;
use JSON;
use URI;
use URI::Escape;
use Digest::SHA;
use AnyEvent::HTTP;

use Net::OAuth;
use Net::OAuth::ProtectedResourceRequest;
use Net::OAuth::RequestTokenRequest;
use Net::OAuth::AccessTokenRequest;

$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;

our %PATH = (
    site          => 'https://twitter.com/',
    request_token => 'https://api.twitter.com/oauth/request_token',
    authorize     => 'https://api.twitter.com/oauth/authorize',
    access_token  => 'https://api.twitter.com/oauth/access_token',
    authenticate  => 'https://api.twitter.com/oauth/authenticate',
);

sub new {
    my ($class, %args) = @_;

    $args{access_token}        ||= $args{token};
    $args{access_token_secret} ||= $args{token_secret};

    my @required = qw(access_token access_token_secret consumer_key consumer_secret);
    for my $item (@required) {
         defined $args{$item} or Carp::croak "$item is required";
    }

    return bless { %args }, $class;
}

sub get {
    my $cb = pop;
    my ($self, $endpoint, $params) = @_;

    my $type = $endpoint =~ /^http.+\.json$/ ? 'url' : 'api';
    $self->request($type => $endpoint, method => 'GET', params => $params, $cb);

    return $self;
}

sub post {
    my ($self, $endpoint, $params, $cb) = @_;

    my $type = $endpoint =~ /^http.+\.json$/ ? 'url' : 'api';
    $self->request($type => $endpoint, method => 'POST', params => $params, $cb);

    return $self;
}

sub request {
    my $cb = pop;
    my ($self, %opt) = @_;

    ($opt{api} || $opt{url})
        or Carp::croak "'api' or 'url' option is required";

    my $url = $opt{url} || 'http://api.twitter.com/1/' . $opt{api} . '.json';

    ref $cb eq 'CODE'
        or Carp::croak "callback coderef is required";

    $opt{params} ||= {};
    ref $opt{params} eq 'HASH'
        or Carp::croak "parameters must be hashref.";

    $opt{method} = uc $opt{method};
    $opt{method} =~ /^(?:GET|POST)$/
        or Carp::croak "'method' option should be GET or POST";

    my $req = $self->_make_oauth_request(
        class => 'Net::OAuth::ProtectedResourceRequest',
        request_url     => $url,
        request_method  => $opt{method},
        extra_params    => $opt{params},
        consumer_key    => $self->{consumer_key},
        consumer_secret => $self->{consumer_secret},
        token           => $self->{access_token},
        token_secret    => $self->{access_token_secret},
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
            $cb->($hdr, $json, $@ ? "parse error: $@" : $hdr->{Reason});
        } else {
            $cb->($hdr, undef, $hdr->{Reason});
        }
    };

    return $self;
}

sub _make_oauth_request {
    my $self  = shift;
    my %opt   = @_;
    my $class = delete $opt{class};

    local $Net::OAuth::SKIP_UTF8_DOUBLE_ENCODE_CHECK = 1;
    my $req = $class->new(
        version   => '1.0',
        timestamp => time,
        nonce     => Digest::SHA::sha1_base64(time . $$ . rand),
        signature_method => 'HMAC-SHA1',
        %opt,
    );
    $req->sign;

    return $req;
}

sub get_request_token {
    my ($class, %args) = @_;

    my @required = qw(consumer_key consumer_secret callback_url);
    for my $item (@required) {
        defined $args{$item} or Carp::croak "$item is required";
    }

    ref $args{cb} eq 'CODE'
        or Carp::croak "cb must be callback coderef";

    $args{auth} ||= 'authorize';

    my $req = __PACKAGE__->_make_oauth_request(
        class => 'Net::OAuth::RequestTokenRequest',
        request_method  => 'GET',
        request_url     => $PATH{request_token},
        consumer_key    => $args{consumer_key},
        consumer_secret => $args{consumer_secret},
        callback        => $args{callback_url},
    );

    AnyEvent::HTTP::http_request GET => $req->to_url, sub {
        my ($body, $header) = @_;
        my %token = __PACKAGE__->_parse_response($body);
        my $location = URI->new($PATH{ $args{auth} });
        $location->query_form(%token);

        $args{cb}->($location->as_string, \%token, $body, $header);
    };
}

sub get_access_token {
    my ($class, %args) = @_;

    my @required = qw(
        consumer_key consumer_secret
        oauth_token  oauth_token_secret oauth_verifier
    );

    for my $item (@required) {
        defined $args{$item} or Carp::croak "$item is required";
    }

    ref $args{cb} eq 'CODE'
        or Carp::croak "cb must be callback coderef";

    my $req = __PACKAGE__->_make_oauth_request(
        class => 'Net::OAuth::AccessTokenRequest',
        request_method  => 'GET',
        request_url     => $PATH{access_token},
        consumer_key    => $args{consumer_key},
        consumer_secret => $args{consumer_secret},
        token           => $args{oauth_token},
        token_secret    => $args{oauth_token_secret},
        verifier        => $args{oauth_verifier},
    );

    AnyEvent::HTTP::http_request GET => $req->to_url, sub {
        my ($body, $header) = @_;
        my %response = __PACKAGE__->_parse_response($body);
        $args{cb}->(\%response, $body, $header);
    };
}

sub _parse_response {
    my ($class, $body) = @_;

    my %query;
    for my $pair (split /&/, $body) {
        my ($key, $value) = split /=/, $pair;
        $query{$key} = URI::Escape::uri_unescape($value);
    }

    return %query;
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
        consumer_key    => 'consumer_key',
        consumer_secret => 'consumer_secret',
        token           => 'access_token',
        token_secret    => 'access_token_secret',
    );

    # or

    my $ua = AnyEvent::Twitter->new(
        consumer_key        => 'consumer_key',
        consumer_secret     => 'consumer_secret',
        access_token        => 'access_token',
        access_token_secret => 'access_token_secret',
    );

    # or, if you use eg/gen_token.pl, you can write simply as:

    my $json_text = slurp 'config.json';
    my $config    = JSON::decode_json($json_text);
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

            if ($res) {
                print "ratelimit-remaining : ", $hdr->{'x-ratelimit-remaining'}, "\n",
                      "x-ratelimit-reset   : ", $hdr->{'x-ratelimit-reset'}, "\n",
                      "screen_name         : ", $res->{screen_name}, "\n";
            } else {
                say $reason;
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

=item C<consumer_key>

=item C<consumer_secret>

=item C<access_token> (or C<token>)

=item C<access_token_secret> (or C<token_secret>)

=back

=head2 get

=over 4

=item C<< $ua->get($api, sub {}) >>

=item C<< $ua->get($api, \%params, sub {}) >>

=item C<< $ua->get($url, sub {}) >>

=item C<< $ua->get($url, \%params, sub {}) >>

=back

=head2 post

=over 4

=item C<< $ua->post($api, \%params, sub {}) >>

=item C<< $ua->post($url, \%params, sub {}) >>

=back

=head2 request

These parameters are required.

=over 4

=item C<api> or C<url>

The C<api> parameter is a shortcut option.

If you want to specify the API C<url>, the C<url> parameter is good for you. The format should be 'json'.

The C<api> parameter will be internally processed as:

    $url = 'http://api.twitter.com/1/' . $opt{api} . '.json';

You can check available C<api>s at L<API Documentation|https://dev.twitter.com/docs/api>

=item C<method> and C<params>

Investigate the HTTP method and required parameters of Twitter API that you want to use.
Then specify it. GET and POST methods are allowed. You can omit C<params> if Twitter API doesn't require it.

=item callback

This module is AnyEvent::HTTP style, so you have to pass the callback (coderef).

Passed callback will be called with C<$header>, C<$response> and C<$reason>.
If something is wrong with the response from Twitter API, C<$response> will be C<undef>. So you can check the value like below.

    sub {
        my ($header, $response, $reason) = @_;

        if ($response) {
            say $response->{screen_name};
        } else {
            say $reason;
        }
    }

=back

=head1 TESTS

Most of all tests are written as author tests since this module depends on remote API server.
So if you want read code that works well, take a look at C<xt/> directory.

=head1 EXPERIMENTAL METHODS

Methods listed below are experimental feature. So interfaces or returned values may vary in the future.

=head2 C<< AnyEvent::Twitter->get_request_token >>

    AnyEvent::Twitter->get_request_token(
        consumer_key    => $consumer_key,
        consumer_secret => $consumer_secret,
        callback_url    => 'http://example.com/callback',
        # auth => 'authenticate',
        cb => sub {
            my ($location, $response, $body, $header) = @_;
            # $location is the endpoint where users are asked the permission
            # $response is a hashref of parsed body
            # $body is raw response itself
            # $header is response headers
        },
    );

=head2 C<< AnyEvent::Twitter->get_access_token >>

    AnyEvent::Twitter->get_access_token(
        consumer_key       => $consumer_key,
        consumer_secret    => $consumer_secret,
        oauth_token        => $oauth_token,
        oauth_token_secret => $oauth_token_secret,
        oauth_verifier     => $oauth_verifier,
        cb => sub {
            my ($token, $body, $header) = @_;
            # $token is the parsed body
            # $body is raw response
            # $header is response headers
        },
    );

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
