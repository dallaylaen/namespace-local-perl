package namespace::local;

use strictures 2;
use B::Hooks::EndOfScope 'on_scope_end';


sub import {
    my $caller = caller;

    my %symbol_copy = do {
        no strict 'refs';
        %{ $caller."::" };
    };

    on_scope_end {
        no strict 'refs';
        no warnings 'redefine';
        %{ $caller."::" } = %symbol_copy;
    };
};

1;
