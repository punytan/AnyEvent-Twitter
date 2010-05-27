use inc::Module::Install;
name 'AnyEvent-Twitter';
all_from 'lib/AnyEvent/Twitter.pm';

requires 'JSON';
requires 'Net::OAuth';
requires 'Net::Twitter::Lite'; # for eg/gen_token.pl
requires 'Digest::SHA';
requires 'AnyEvent';
requires 'AnyEvent::HTTP';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
auto_set_repository;
auto_include;
WriteAll;
