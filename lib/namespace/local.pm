package namespace::local;

use strictures 2;
use B::Hooks::EndOfScope 'on_scope_end';

sub import {
    my $caller = caller;

    my @names = get_syms( $caller );

    my %content;
    foreach my $name( @names ) {
        $content{$name} = save_glob( $caller, $name );
    };

    warn "Got names: ".join " ", sort grep { !m,::|/, } @names;

    on_scope_end {
        warn "Reached end";
        erase_syms( $caller );
        foreach my $name (@names) {
            restore_glob( $caller, $name, $content{$name} )
        };
    };
};

sub get_syms {
    my $package = shift;

    no strict 'refs';
    return keys %{ $package."::" };
};

sub erase_syms {
    my $package = shift;

    no strict 'refs';
    %{ $package."::" } = ();
};

my @TYPES = qw(SCALAR ARRAY HASH CODE);
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

    warn "Restoring $package :: $name as ".join " ", sort keys %$copy;

    no strict 'refs';
    foreach my $type ( keys %$copy ) {
        *{ $package."::".$name } = $copy->{$type}
    };
};

1;
