#!perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

# Ouch...

# We'll test nesting of namespace::local.
# To do so, we'll try calling blessed() and looks_like_number()
# from Scalar::Util from different scopes

# Note that we can't define subs inside a guarded scope
# as namespace::local will (as of current) erase them

{
    package Foo;

    # this block knows nothing of imports
    sub dies_before {
        return blessed({});
    };

    # scope: before, inner, after
    # action: blessed, looks_like_number
    sub scope {
        my ($scope, $action) = @_;

        if ($scope eq 'before') {
            # this block is repeated a few times
            # basically it's "die unless I know this sub"
            return blessed({}) if $action eq 'blessed';
            return looks_like_number(10) if $action eq 'number';
            die "must not reach this";
        };

        # the outer scope starts
        use namespace::local;
        use Scalar::Util qw(blessed);

        if ($scope eq 'inner') {
            # this is nested scope for which this test has been built
            use namespace::local;
            use Scalar::Util qw(looks_like_number);

            return blessed({}) if $action eq 'blessed';
            return looks_like_number(10) if $action eq 'number';
            die "must not reach this";
        };

        # nested scope has ended, shall not affect outer's import though
        if ($scope eq 'after') {
            return blessed({}) if $action eq 'blessed';
            return looks_like_number(10) if $action eq 'number';
            die "must not reach this";
        };

        die "must not reach this";
    };

    #  this block also knows nothing of imports
    sub dies_after {
        return blessed({});
    };

}; # /package Foo

throws_ok {
    Foo::dies_before()
} qr/ndefined subroutine\b.*\bFoo::blessed/;

throws_ok {
    Foo::dies_after()
} qr/ndefined subroutine\b.*\bFoo::blessed/;


throws_ok {
    Foo::scope( 'before', 'blessed');
} qr/ndefined subroutine\b.*\bFoo::blessed/;

throws_ok {
    Foo::scope( 'before', 'number');
} qr/ndefined subroutine\b.*\bFoo::looks_l/;

lives_ok {
    Foo::scope( 'inner', 'blessed' );
};

lives_ok {
    Foo::scope( 'inner', 'number' );
};

lives_ok {
    Foo::scope( 'after', 'blessed' );
};

throws_ok {
    Foo::scope( 'after', 'number');
} qr/ndefined subroutine\b.*\bFoo::looks_l/;


done_testing;
