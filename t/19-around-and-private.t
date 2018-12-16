#!perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

my $package = do {
    package Foo;

    sub public {
        use namespace::local;
        return private();
    };

    sub private {
        42;
    };

    __PACKAGE__;
};

ok $package->can("public"), "public sub available";
ok $package->can("private"), "private sub available (no masking)";

TODO: {
    local $TODO = "known bug in namespace::local";
    lives_ok {
        is $package->public, 42, "value as expected";
    } "call lives";
};

done_testing;
