#!perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

{
    package Bar;
    sub bar { 42 };
};

{
    package Foo;
    BEGIN { our @ISA = qw(Bar); };
    use namespace::local -above;
};

is_deeply \@Foo::ISA, ["Bar"], "\@ISA as expected";
lives_ok {
    is( Foo->bar, 42, "inherited method propagates" );
} "method didn't die";

done_testing;
