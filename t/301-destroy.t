#!perl

use strict;
use warnings;
use Test::More;

my @trace;
{
    package Foo;
    sub new { bless {}, shift };
    use namespace::local -below;
    our @DESTROY = qw(foo bar);
    sub DESTROY { push @trace, \@DESTROY };
};

is_deeply \@Foo::DESTROY, [], "\@DESTROY array looks empty from the outside";

my $foo = Foo->new;

is_deeply \@trace, [], "no destroy called";

undef $foo;

is_deeply \@trace, [[qw[foo bar]]], "destroy called once, data in array not deleted";

done_testing;
