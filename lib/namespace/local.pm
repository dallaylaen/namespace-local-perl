package namespace::local;

use strict;
use warnings;
use B::Hooks::EndOfScope 'on_scope_end';

sub import {
    my $caller = caller;

    my @names = get_syms( $caller );

    my %content;
    foreach my $name( @names ) {
        $content{$name} = save_glob( $caller, $name );
    };

    on_scope_end {
        erase_syms( $caller );
        foreach my $name (@names) {
            restore_glob( $caller, $name, $content{$name} )
        };
    };
};

sub get_syms {
    my $package = shift;

    no strict 'refs';
    return sort grep { /^\w+$/ } keys %{ $package."::" };
};

sub erase_syms {
    my $package = shift;

    foreach my $name( get_syms( $package ) ) {
        no strict 'refs';
        delete ${ $package."::" }{$name};
    };
};

# Don't touch NAME, PACKAGE, and GLOB itself
my @TYPES = qw(SCALAR ARRAY HASH CODE IO FORMAT);
sub save_glob {
    my ($package, $name) = @_;
    my $copy;

    foreach my $type (@TYPES) {
        no strict 'refs';
        my $value = *{$package."::".$name}{$type};
        $copy->{$type} = $value if defined $value;
    };

    return $copy;
};

sub restore_glob {
    my ($package, $name, $copy) = @_;
    die "ouch" unless ref $copy eq 'HASH';

    foreach my $type ( @TYPES ) {
        defined $copy->{$type} or next;
        no strict 'refs';
        *{ $package."::".$name } = $copy->{$type}
    };
};

1;
