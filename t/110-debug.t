#!perl

use strict;
use warnings;
use Test::More;

BEGIN {
    $ENV{PERL_NAMESPACE_LOCAL} = 'debug';
};

my @trace;

BEGIN {
    $SIG{__WARN__} = sub { push @trace, shift };
};

BEGIN {
    package Foo;

    sub public {
        _private();
    };

    sub _private {
        42;
    };

    use namespace::local -target => "Foo", -only => qr/^_/, -above;
};

BEGIN {
    undef $SIG{__WARN__};
};

is scalar @trace, 1, "1 warning issued";
like $trace[0], qr/_private\{CODE\}=undef/, "debugging info present";
like $trace[0], qr/namespace::local/, "namespace::local signed";

ok !Foo->can("_private"), "private function masked";
ok +Foo->can("public"), "public function still there";
is +Foo->public, 42, "Value as expected";

diag "WARN: $_" for @trace;

done_testing;
