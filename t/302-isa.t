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
    sub ISA { 137 };
    use namespace::local -above;
    sub public { ISA() };
};

is_deeply \@Foo::ISA, ["Bar"], "\@ISA as expected";
lives_ok {
    is( Foo->bar, 42, "inherited method propagates" );
} "method didn't die";

ok !Foo->can("ISA"), "sub ISA masked";
lives_ok {
    is +Foo->public, 137, "masked sub propagates within package";
} "public function works as expected";

done_testing;
