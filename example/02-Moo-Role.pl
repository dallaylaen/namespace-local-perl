#!/usr/bin/env perl

use strict;
use warnings;

{
    package My::Role;
    use Moo::Role;

    sub public {
        return _private(@_);
    };

    use namespace::local -below;
    sub _private {
        return 42;
    };

    1;
};

{
    package My::Class;
    use Moo;

    with 'My::Role';
};

my $x = My::Class->new;

eval {
    print $x->public, "\n";
    print $x->_private, "\n"; # this dies
};
warn $@ if $@;
