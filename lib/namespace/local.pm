package namespace::local;

use strictures 2;
use B::Hooks::EndOfScope 'on_scope_end';

use Data::Dumper;

sub import {
    my $caller = caller;

    my @names = get_syms( $caller );

    my %content;
    $content{$_} = save_glob( $caller, $_ )
        for @names;

    warn join " ", sort grep { !m,::|/, } keys %content;

    on_scope_end {
        warn "Reached end";
        erase_syms( $caller );
        restore_glob( $caller, $_, $content{$_} )
            for @names;
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

    {
        no strict 'refs';
        $copy->{$_} = *{$package."::".$name}{$_} for @TYPES;
    };

    defined $copy->{$_} or delete $copy->{$_} for keys %$copy;

    return $copy;
};

sub restore_glob {
    my ($package, $name, $copy) = @_;
    die "ouch" unless ref $copy eq 'HASH';

    warn "Restoring $package :: $name as ".join " ", sort keys %$copy;
#    warn "Restoring sub $name" if $copy->{CODE};

    no strict 'refs';
    defined $copy->{$_} and *{ $package."::".$name } = $copy->{$_}
        for @TYPES;
};

1;
