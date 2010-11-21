#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use JSON;
use Net::Twitter::Lite;

my %p;

print "\n", "Register your app at http://twitter.com/oauth_clients\n\n";

print "Paste your\n";
print "\tconsumer_key    : ";
$p{consumer_key} = <STDIN>;
chomp $p{consumer_key};

print "\tconsumer_secret : ";
$p{consumer_secret} = <STDIN>;
chomp $p{consumer_secret};

my $nt = Net::Twitter::Lite->new(%p);

print "\n",
    "Access the authorization URL and get the PIN at \n\n",
    $nt->get_authorization_url,
    "\n\n";

print "\tInput the PIN   : ";
my $pin = <STDIN>;
chomp $pin;

($p{access_token}, $p{access_token_secret}) = $nt->request_access_token(verifier => $pin);
print "\n",
      "access_token        is $p{access_token}\n",
      "access_token_secret is $p{access_token_secret}\n\n",
      "Do you want to save these parameters to a file? [y/N] : ";

my $out = <STDIN>;
chomp $out;

if ($out && $out =~ /y/i) {
    print "\n",
          "You can save it as JSON.\n",
          "Input the file name to save : ";
    my $file = <STDIN>;
    chomp $file;

    print "\n",
          "Which style do you prefer?\n",
          "\t1) Old style for AnyEvent::Twitter\n",
          "\t2) New style for AnyEvent::Twitter, which is compatible with AnyEvent::Twitter::Stream (recommended)\n",
          "[ 1 / 2 ] : ";

    my $style = <STDIN>;
    chomp $style;

    open my $fh, '>', $file or die $!;

    if ($style eq '1') {
        print {$fh} encode_json(\%p);
    } elsif ($style eq '2') {
        my %new = (
            consumer_key    => $p{consumer_key},
            consumer_secret => $p{consumer_secret},
            token           => $p{access_token},
            token_secret    => $p{access_token_secret},
        );

        print {$fh} encode_json(\%new);
    } else {
        die "Unknown option";
    }

    close $fh or die $!;

    print "\n",
          "Check $file now!\n";
}

print "Done.\n\n";

exit;

__END__

