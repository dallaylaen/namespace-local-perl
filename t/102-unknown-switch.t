#!perl

use strict;
use warnings;
use Test::More;
use Test::Exception;

require namespace::local; # not use

throws_ok {
    namespace::local->import( "-foobar" );
} qr/^namespace::local:.*nknown.*-foobar/, "descriptive error";

throws_ok {
    namespace::local->import( -except => {} );
} qr/^namespace::local:.* -except .* must be/, "descriptive error (-except)";

throws_ok {
    namespace::local->import( -except => [ '~www' ] );
} qr/^namespace::local: cannot exempt.*~www\b/, "descriptive error (-except, bad symbol)";

throws_ok {
    namespace::local->import( -only => 'foobar' );
} qr/^namespace::local:.* -only .* must be/, "descriptive error (-only)";

done_testing;
