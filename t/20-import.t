#!perl

use strict;
use warnings;
use Test::More;
use Test::Warn;

my @trace;
{
    package Foo;
    use namespace::local;

    our @import = qw(foo bar);

    sub import {
        push @trace, [shift, @import];
    };
};

warnings_like {
    is_deeply \@trace, [], "No import called";
    Foo->import;
    is_deeply \@trace, [[ "Foo", "foo", "bar" ]], "import called once";

    is_deeply \@Foo::import, [], "\@Foo::import hidden";
} [], "no warnings overall";

done_testing;
