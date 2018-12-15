#!perl

use strict;
use warnings;
use Test::More tests => 1;

my $module = 'namespace::local';
require_ok $module
    or print "Bail out! Failed to load $module: $@";

diag( "Testing $module $namespace::local::VERSION, Perl $], $^X" );
