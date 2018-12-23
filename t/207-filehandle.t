#!perl

use strict;
use warnings;
use Test::More;
use Test::Warn;

my $buffer;

{
    use namespace::local;
    open FD, ">", \$buffer ## no critic
        or die "Failed to open fake file: $!";

    print FD "Hello\n"; ## no critic
};

warnings_like {
    # we use -Mwarnings=FATAL,all in pre-commit hook
    # so counter it
    use warnings NONFATAL => qw(unopened);

    # twice to get rid of a "once" warning
    print FD "Goodbye\n"; ## no critic
    print FD "Goodbye\n"; ## no critic
} [
    qr(print\b.* on unopened filehandle),
    qr(print\b.* on unopened filehandle),
], "filehandle is unknown";

is $buffer, "Hello\n", "only first write succeeded";

done_testing;
