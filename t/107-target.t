#!perl

use strict;
use warnings;
use Test::More;

{
    package Foo;
    sub quux { 42 };
};

{
    package Bar;
    sub quux { 137 };
    # using -above, so that things _already_ in Foo:: start being removed
    use namespace::local -above, -target => "Foo";
};

ok !!Bar->can( "quux" ), "quux in Bar stays";
ok  !Foo->can( "quux" ), "quux in Foo removed";

done_testing;
