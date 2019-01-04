#!perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

{
    package Foo;

    sub before {
        private() + private2();
    };

    use namespace::local;
    sub private {
        42;
    };
    no namespace::local;

    sub between {
        private2();
    };

    use namespace::local;
    sub private2 {
        137;
    };
    no namespace::local;

    sub after {
        private() + private2();
    };
};

ok +Foo->can("before"),   "public sub unmasked";
ok !Foo->can("private"),  "between use and no";
ok +Foo->can("between"),  "public sub unmasked (between blocks)";
ok !Foo->can("private2"), "between use and no (2)";
ok +Foo->can("after"),    "public sub unmasked (again)";

lives_ok {
    is Foo::before(), 42+137, "private sub propagates";
} "code lives";

lives_ok {
    is Foo::between(), 137, "private sub propagates";
} "code lives";

throws_ok {
    is Foo::after(), -1, "deliberately failing test";
} qr/ndefined subroutine.*private/, "inner sub (not outer one) is unknown";



done_testing;
