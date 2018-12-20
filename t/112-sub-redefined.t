#!perl

use strict;
use warnings;
use Test::More;

{
    package Foo;
    sub bar { 42 };
    sub before { bar() };

    {
        use namespace::local -except => ['inner'];
        no warnings 'redefine';
        sub bar { 137 };
        sub inner { bar() };
    };

    sub after { bar() };
};

is +Foo->before, 42, "old value";
is +Foo->inner, 137, "localized value";
is +Foo->after, 42, "restored value";

done_testing;


