#!perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

{
    package Foo;
    use Scalar::Util qw( reftype );
    use namespace::local -above;

    sub bar {
        use namespace::local;
        use Carp;
        croak "a deliberate exception in bar(): ".reftype({});
    };

    use namespace::local -below;
    sub unused {};
};

throws_ok {
    Foo->bar;
} qr/a deliberate exception in bar.*HASH/, "bar() works as expected";

ok !Foo->can("croak"), "Foo cannot croak";
ok !Foo->can("refaddr"), "Foo cannot refaddr";

done_testing;
