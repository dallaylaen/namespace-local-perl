#!/usr/bin/env perl

use strictures 2;
use Test::More;
use Test::Exception;

use Assert::Refute {};

my $report = try_refute {
    use namespace::local "like";
    use Assert::Refute qw(like ok);

    like "foo", qr/bar/, "A failed test";
};

is $report->get_sign, "tNd", "report contains failed test";
like "foo", qr/(.)\1/, "normal like here";

throws_ok {
    like "#Anchored", "Anchored", "FAILED! This is A::R like";
} "like does not accept plain scalar";

done_testing;
