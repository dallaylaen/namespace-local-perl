#!perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

{
    package Foo;
    use Moo;
    use namespace::local -above;

    sub bar {
        use namespace::local;
        use Carp;
        croak "a deliberate exception in bar()";
    };

    use namespace::local -below;
    sub unused {};
};

throws_ok {
    Foo->bar;
} qr/a deliberate exception in bar()/, "bar() works as expected";

ok !Foo->can("croak"), "Foo cannot croak";
ok !Foo->can("has"), "Foo cannot has";
ok +Foo->can("new"), "Foo can new() still";

done_testing;
