#!perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

#1
subtest "all three at once" => sub {
    my $package = do {
        package All;
        sub n_above { 42 };
        use namespace::local -above;

        sub inner {
            use namespace::local;

            use Scalar::Util qw(looks_like_number);
            return looks_like_number( 3.14 ) + n_above() + n_below();
        };

        use namespace::local -below;

        sub n_below { 137 };
        __PACKAGE__;
    };

    ok !$package->can("n_above"), "upper sub removed";
    ok !$package->can("looks_like_number"), "inner sub removed";
    ok !$package->can("n_below"), "below sub removed";
    ok +$package->can("inner"), "only public sub left";

    local $TODO = "Known bug";
    lives_ok {
        is +$package->inner, 42+137+1, "All worked";
    } "code lives";
};

# TODO add more tests

done_testing;
