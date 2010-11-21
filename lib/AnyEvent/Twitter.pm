package AnyEvent::Twitter;
use strict;
use warnings;
use utf8;
use 5.008;
use Encode;
our $VERSION = '0.52';

use Carp;
use JSON;
use Net::OAuth;
use Digest::SHA;
use AnyEvent::HTTP;

$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;

sub new {
    my $class = shift;
    my %args  = @_;

    if (defined $args{token}) {
        $args{access_token} = $args{token};
    }

    if (defined $args{token_secret}) {
        $args{access_token_secret} = $args{token_secret};
    }

    defined $args{consumer_key}        or croak "consumer_key is needed";
    defined $args{consumer_secret}     or croak "consumer_secret is needed";
    defined $args{access_token}        or croak "access_token is needed";
    defined $args{access_token_secret} or croak "access_token_secret is needed";

    return bless \%args, $class;
}

sub get {
    my $self = shift;
    my $api  = shift;
    my $cb   = pop;
    my $params = shift;

    if (not defined $params) {
        $params = {};
    } elsif (ref $params ne 'HASH') {
        croak "parameters must be hashref.";
    }

    my @target;
    if ($api =~ /^http/) {
        if ($api =~ /.json$/) {
            push @target, 'url', $api;
        } else {
            croak "url must end with '.json'. The argument is $api";
        }
    } else {
        push @target, 'api', $api;
    }

    $self->request(@target, method => 'GET', params => $params, $cb);

    return $self;
}

sub post {
    my $self = shift;
    my ($api, $params, $cb) = @_;

    ref $params eq 'HASH' or croak "parameters must be hashref.";

    my @target;
    if ($api =~ /^http.+\.json$/) {
        push @target, 'url', $api;
    } else {
        push @target, 'api', $api;
    }

    $self->request(@target, method => 'POST', params => $params, $cb);

    return $self;
}

sub request {
    my $self = shift;
    my $cb   = pop;
    my %opt  = @_;

    my $url;
    if (defined $opt{url}) {
        $url = $opt{url};
    } elsif (defined $opt{api}) {
        $url = 'http://api.twitter.com/1/' . $opt{api} . '.json';
    } else {
        croak "'api' or 'url' option is required";
    }

    ref $cb eq 'CODE'    or croak "callback coderef is required";
    defined $opt{method} or croak "'method' option is required";

    $opt{method} = uc $opt{method};
    $opt{method} =~ /^(?:GET|POST)$/ or croak "'method' option should be GET or POST";

    my $req = $self->_make_oauth_request(
        request_url    => $url,
        request_method => $opt{method},
        extra_params   => $opt{params},
    );

    my $req_url;
    my %req_params;
    if ($opt{method} eq 'POST') {
        $req_params{body} = $req->to_post_body;
        $req_url = $req->normalized_request_url;
    } else {
        $req_url = $req->to_url;
    }

    http_request($opt{method} => $req_url, %req_params, sub {
        my ($body, $hdr) = @_;

        if ($hdr->{Status} =~ /^2/) {
            local $@;
            my $json = eval { decode_json($body) };
            $cb->($hdr, $json, $@ ? "parse error: $@" : $hdr->{Reason}) ;
        } else {
            $cb->($hdr, undef, $hdr->{Reason});
        }
    });

    return $self;
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

    return $req;
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
        my ($hdr, $res, $reason) = @_;

        say $res->{screen_name};
        $cv->end;
    });

    # GET request with parameters
    $cv->begin;
    $ua->get('account/verify_credentials', {include_entities => 1}, sub {
        my ($hdr, $res, $reason) = @_;

        say $res->{screen_name};
        $cv->end;
    });

    # POST request with parameters
    $cv->begin;
    $ua->post('statuses/update', {status => 'いろはにほへと ちりぬるを'}, sub {
        my ($hdr, $res, $reason) = @_;

        say $res->{user}{screen_name};
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

You can check the C<api> option at L<Twitter API Wiki|http://apiwiki.twitter.com/Twitter-API-Documentation>

=item method and params

Investigate the HTTP method and required parameters of Twitter API that you want to use.
Then specify it. GET/POST methods are allowed. You can omit C<params> if Twitter API doesn't requires option.

=item callback

This module is AnyEvent::HTTP style, so you have to pass the coderef callback.

Passed callback will be called with C<$hdr>, C<$response> and C<$reason>.
If something is wrong with the response from Twitter API, C<$response> will be C<undef>. So you can check the value like below.

    sub {
        my ($hdr, $res, $reason) = @_;

        unless ($res) {
            print $reason, "\n";
        } else {
            print $res->{screen_name}, "\n";
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
