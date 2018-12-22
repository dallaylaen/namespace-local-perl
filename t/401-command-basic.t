#!perl

use strict;
use warnings;
use Test::More;
use Test::Warn;
use Test::Exception;

$ENV{PERL_NAMESPACE_LOCAL} = 'debug';

require namespace::local; # no import!

{
    package Foo;

    sub new { bless {}, shift };

    sub hidden { 42 };
};


my $cmd = namespace::local->new( target => 'Foo' );

my $table = $cmd->read_symbols;

is_deeply $table->{new}, { CODE => Foo->can("new"), SCALAR => \undef }
    , "can read table";

my $foo = Foo->new;
ok $foo->can( "hidden" ), "hidden not hidden yet";

warnings_like {
    $cmd->replace_symbols( [ "hidden" ] );
} [ { carped => qr/\*hidden\{CODE\}=undef/ } ], "debugging info present";

ok !$foo->can( "hidden" ), "hidden is hidden now";

warnings_like {
    $cmd->replace_symbols( [], $table );
} [ { carped => qr/\*hidden\{CODE\}=CODE/ } ], "debugging info present";

lives_ok {
    is $foo->hidden, 42, "same sub restored";
} "hidden available again";

done_testing;
