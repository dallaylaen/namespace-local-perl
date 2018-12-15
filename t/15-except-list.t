#!perl

use strict;
use warnings;
use Test::More;

{
    package Foo;
    use namespace::local -except => [qw[ @array function ]];

    sub function {
        private();
    };

    our @array = qw(foo bar);
    our @disappear = @array;

    sub array {
        die "This does not exist";
    };

    sub private {
        42;
    };
};

ok !!Foo->can("function"), "function preserved";
ok  !Foo->can("private"), "private() erased";
ok  !Foo->can("array"), "private array() erased";

is_deeply \@Foo::array, [qw[foo bar]], "\@array preserved";
is_deeply \@Foo::disappear, [], "private array erased";
# repeat test to avoid a 'once' warning
is_deeply \@Foo::disappear, [], "private array erased";

done_testing;
