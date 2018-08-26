#!/usr/bin/env perl

use strictures 2;
use Test::More;
use Test::Exception;

use Scalar::Util qw(refaddr);

do {
    use namespace::local;
    use Scalar::Util qw(blessed);

    lives_ok {
        ok !blessed {}, "Blessed works";
        is blessed( bless {}, "Foo" ), "Foo", "blessed round-trip";
    } "blesses lives";
};

throws_ok {
        is blessed( bless {}, "Foo" ), "Foo", "blessed round-trip";
} qr/Undefined subroutine.*main::blessed/;

lives_ok {
    like refaddr {}, qr/\d+/, "refaddr check";
} "refaddr available because imported b4";

done_testing;

