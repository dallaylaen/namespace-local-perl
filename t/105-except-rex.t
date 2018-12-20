#!perl

use strict;
use warnings;
use Test::More;

{
    package Foo;
    use namespace::local -except => qr(test);

    sub test_me {
    };

    sub production_me {
    };
};

ok !!Foo->can( "test_me" ), "exception worked";
ok  !Foo->can( "production_me" ), "everything else masked";

done_testing;
