#!perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

{
    package Foo;
    use namespace::local -only => qr/^test/;

    sub public {
        return test_foo() + test_bar();
    };

    sub test_foo { 42 };
    sub test_bar { 137 };
};

lives_ok {
    is +Foo->public, 42+137, "value as expected";
} "can public()";

ok !Foo->can("test_foo"), "test_foo removed";
ok !Foo->can("test_bar"), "test_bar removed";

done_testing;
