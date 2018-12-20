#!perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

my $package = do {
    package Foo;

    sub above {
        return private() + 1;
    };

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
ok $package->can("private"), "private sub available (no masking was requested)";

lives_ok {
    is $package->public, 42, "value as expected";
} "inner lives";

lives_ok {
    is $package->above, 43, "value as expected";
} "above lives";

done_testing;
