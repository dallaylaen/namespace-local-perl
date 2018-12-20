#!perl

use strict;
use warnings;
use Test::More;

{
    package Foo;

    use namespace::local -only => [ '$function', 'value' ];

    our $function = 42;
    sub function { return value(); };

    our $value = 137;
    sub value { return $function; };
};

is +Foo->function, 42, "hidden value propagates...";
is $Foo::function, undef, "... but remains invisible";

is $Foo::value, 137, "public variable untouched";
ok !Foo->can("value"), "hidden function hidden";

done_testing;

