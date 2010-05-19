use inc::Module::Install;
name 'AnyEvent-Twitter-OAuth';
all_from 'lib/AnyEvent/Twitter/OAuth.pm';

# requires '';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
auto_set_repository;
auto_include;
WriteAll;
