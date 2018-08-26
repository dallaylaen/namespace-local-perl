#!/usr/bin/env perl

use strictures 2;
use Test::More;
use Test::Exception;

use Assert::Refute {};

my $report = try_refute {
    use namespace::local;
    use Assert::Refute qw(like unlike);

    like "foo", "bar", "FAILED: like should be confined";
    unlike "foo", qr/foo/, "FAILED: unlike should be confined";
};

is $report->get_sign, "tNNd", "report contains failed test";
like "foo", qr/(.)\1/, "normal like here";

done_testing;
