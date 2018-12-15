#!perl

use strict;
use warnings;
use Test::More;
use Test::CleanNamespaces;

{
    package Foo;
    use Moo;
    use Carp;
    use namespace::local -above;

    sub bar {
        private();
    };

    use namespace::local -below;
    sub private {
        42;
    };
};

namespaces_clean( "Foo" );

note( Foo->can("carp") );

done_testing;

