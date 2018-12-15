
use 5.008;
use strict;
use warnings FATAL => 'all';

package namespace::local;

our $VERSION = '0.05';

=head1 NAME

namespace::local - Confine imports or functions to a given scope

=head1 SYNOPSIS

This module allows to confine imports or private functions
to a given scope. The following modes of operation exist:

=head2 -around (the default)

This confines all subsequent imports and functions
between the use of L<namespace::local> and the end of scope.

    package My::Package;

    sub normal_sub {
        # frobnicate() is unknown
    }

    sub using_import {
        use namespace::local;
        use Some::Crazy::DSL qw(frobnicate);
        frobnicate Foo => 42;
    }

    sub no_import {
        # frobnicate() is unknown
    }

=head2 -below

Hides subsequent imports and functions on end of scope.

This may be used to mask private functions:

    package My::Package;
    use Moo::Role;

    # This is available everywhere
    sub public {
        return private();
    };

    use namespace::local -below;

    # This is only available in the current file
    sub private {
        return 42;
    };

Note that this doesn't work for private I<methods> since methods
are resolved at runtime.

=head2 -above

Hide all functions and exports above the use line.

This emulates L<namespace::clean>, by which this module is clearly inspired.

    package My::Module;
    use POSIX;
    use Time::HiRes;
    use Carp;
    use namespace::local -above;

    # now define public functions here

=head1 OPTIONS

Extra options may be passed to namespace::local:

=head2 -except <regex>

Exempt names matching the regular expression from namespace modification.

=head1 EXEMPTIONS

The following symbols are not touched by this module, to avoid breaking things:

=over

=item * anything that does not consist of word characters;

=item * $_, @_, $1, $2, ...;

=item * Arrays: C<@CARP_NOT>, C<@EXPORT>, C<@EXPORT_OK>, C<@ISA>;

=item * Scalars: C<$AUTOLOAD>, C<$a>, C<$b>;

=item * Files: C<DATA>, C<STDERR>, C<STDIN>, C<STDOUT>;

=item * Functions: C<AUTOLOAD>, C<DESTROY>, C<import>;

=back

This list is likely incomplete, and may grow in the future.

=head1 METHOD/FUNCTIONS

None.

=head1 CAVEATS

This module is highly experimental.
The following two conditions are guaranteed to hold
at least until leaving the beta stage:

=over

=item * All symbols available before the use line will stay so
after end of scope

=item * All I<functions> imported I<from other modules> below the use line
with names consisting of words and not present in L<perlvar>
are not going to be available after end of scope.

=back

The rest is a big grey zone.

Currently the module works by saving and then restoring globs,
so variables and filehandles are also reset.
This may be changed in the future.

Due to order of callback execution in L<B::Hooks::EndOfScope>,
other modules in C<namespace::> namespace may interact poorly
with L<namespace::local>.

However, at least C<-above> and C<-below> switches
work as expected if used simultaneously.

=cut

use Carp;

# this was stolen from namespace::clean
use B::Hooks::EndOfScope 'on_scope_end';
use Scalar::Util qw( weaken );

my %known_action;
$known_action{$_}++ for qw(-above -below -around);

my $last_command;

sub import {
    my $class = shift;

    my $opt = $class->_process_options( @_ );

    # on_scope_end callback execution order is direct
    # we need reversed order, so use a stack of commands.
    my $command = namespace::local::_command->new(
        target => delete $opt->{target} || scalar caller );
    $last_command->set_next( $command ) if $last_command;
    $last_command = $command;
    weaken $last_command; # to avoid leaks

    $command->prepare( %$opt );

    on_scope_end {
        $command->execute;
    };
};

sub _process_options {
    my $class = shift;

    my %opt = ( action => '-around' );
    while (@_) {
        my $arg = shift;
        if ( $known_action{$arg} ) {
            $opt{action} = $arg;
        } elsif ($arg eq '-target') {
            $opt{target} = shift;
        } elsif ($arg eq '-except') {
            my $cond = shift;
            if (ref $cond eq 'Regexp') {
                $opt{except_rex} = $cond;
            } else {
                croak "$class: -except argument must be regexp or array"
            };
        } else {
            croak "$class: unknown option $arg";
        };
    };

    return \%opt;
};

# Hide internal OO engine
# Maybe it will be released later...

package
    namespace::local::_command;

use Carp; # too
our @CARP_NOT = qw(namespace::local);

# target => package_name is required
sub new {
    my ($class, %opt) = @_;

    # TODO check options
    $opt{except_rex} = qr/^[0-9]+$|^-$/; # no matter what, exempt $_, $1, ...

    return bless \%opt, $class;
};

sub set_next {
    my ($self, $next) = @_;
    carp "Next already set"
        if $self->{next};
    $self->{next} = $next;
};

# maybe merge with new?
# don't want a big constructor
sub prepare {
    my ($self, %opt) = @_;

    my $action = $opt{action};

    if (my $rex = $opt{except_rex}) {
        my $old = $self->{except_rex};
        $self->{except_rex} = qr((?:$old)|(?:$rex));
    };

    my $table = $self->read_symbols;

    # FIXME UGLY HACK
    # Immediate backup-and-restore of symbol table
    #     somehow forces binding of symbols
    #     above 'use namespace::local' line
    #     thus preventing subsequent imports from leaking upwards
    # I do not know why it works, it shouldn't.
    if ($action eq '-around') {
        $self->erase_symbols;
        $self->write_symbols( $table );
    };

    if ($action eq '-above' ) {
        $self->{action} = sub {
            $self->erase_only_symbols( $table );
        };
    } else {
        $self->{action} = sub {
            $self->erase_symbols;
            $self->write_symbols( $table );
        };
    };
};

sub execute {
    my ($self) = @_;

    # always execute stacked commands in reverse order
    $self->{next}->execute
        if $self->{next};

    $self->{action}->()
        unless $self->{done}++;
};

# in: package name
# out: sorted & filtered list of symbols

# FIXME needs explanation
# We really need to filter because copying ALL table
#     was preventing on_scope_end from execution
#     (accedental reference count increase?..)

sub read_names {
    my $self = shift;

    my $package = $self->{target};
    my $except = $self->{except_rex};

    my @list = sort grep {
        /^\w+$/ and $_ !~ $except
    } do {
        no strict 'refs'; ## no critic
        keys %{ $package."::" };
    };

    return @list;
};

# Don't touch NAME, PACKAGE, and GLOB itself
my @TYPES = qw(SCALAR ARRAY HASH CODE IO FORMAT);

# Skip some well-known variables and functions
# Format: touch_not{ $name }{ $type }
# NOTE if you change the list, also change the EXEMPTIONS section in the POD.
my %touch_not;
$touch_not{$_}{ARRAY}++  for qw( CARP_NOT EXPORT EXPORT_OK ISA );
$touch_not{$_}{CODE}++   for qw( AUTOLOAD DESTROY import );
$touch_not{$_}{IO}++     for qw( DATA STDERR STDIN STDOUT );
$touch_not{$_}{SCALAR}++ for qw( AUTOLOAD a b );

# In: package
# Out: (none)
# Side effect: destroys symbol table
sub erase_symbols {
    my ($self, $list) = @_;

    my $package = $self->{target};
    $list ||= [ $self->read_names ];

    foreach my $name( @$list ) {
        next if $touch_not{$name};
        no strict 'refs'; ## no critic
        delete ${ $package."::" }{$name};
    };
};

sub erase_only_symbols {
    my ($self, $table) = @_;

    my $package = $self->{target};
    my @list = keys %$table;

    # read all necessary symbols
    my $current = $self->read_symbols( \@list );

    foreach my $name ( @list ) {
        $table->{$name}{$_} and delete $current->{$name}{$_}
            for @TYPES;
    };

    $self->erase_symbols( \@list );
    $self->write_symbols( $current );
};

# In: package, symbol
# Out: a hash with glob content
sub read_symbols {
    my ($self, $list) = @_;

    my $package = $self->{target};
    $list ||= [ $self->read_names ];

    my %content;
    foreach my $name ( @$list ) {
        foreach my $type (@TYPES) {
            my $value = do {
                no strict 'refs'; ## no critic
                *{$package."::".$name}{$type};
            };
            $content{$name}{$type} = $value if defined $value;
        };
    };

    return \%content;
};

# In: package, symbol, hash
# Out: (none)
# Side effect: recreates *package::symbol
sub write_symbols {
    my ($self, $table) = @_;

    my $package = $self->{target};

    foreach my $name( keys %$table ) {
        my $copy = $table->{$name};
        if ( my $skip = $touch_not{$name} ) {
            foreach my $type (keys %$skip) {
                my $value = do {
                    no strict 'refs'; ## no critic
                    *{$package."::".$name}{$type};
                };
                $copy->{$type} = $value if defined $value;
            };
        };

        {
            no strict 'refs'; ## no critic
            delete ${ $package."::" }{$name};
        };

        foreach my $type ( @TYPES ) {
            defined $copy->{$type} or next;
            no strict 'refs'; ## no critic
            *{ $package."::".$name } = $copy->{$type}
        };
    };
};

=head1 AUTHOR

Konstantin S. Uvarin, C<< <khedin at gmail.com> >>

=head1 BUGS

This is experimental module. There certainly are bugs.

Bug reports, feature requests, suggestions and general feedback welcome at:

=over

=item * L<https://github.com/dallaylaen/namespace-local-perl/issues>

=item * L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=namespace-local>

=item * C<bug-namespace-local at rt.cpan.org>

=back

=head1 SUPPORT

You can find documentation for this module with the C<perldoc> command.

    perldoc namespace::local

You can also look for information at:

=over

=item * github:

L<https://github.com/dallaylaen/namespace-local-perl>

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=namespace-local>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/namespace-local>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/namespace-local>

=item * Search CPAN

L<http://search.cpan.org/dist/namespace-local/>

=back

=head1 SEE ALSO

L<namespace::clean>, L<namespace::sweep>, L<namespace::autoclean>...

L<B::Hooks::EndOfScope> is used as a backend.

=head1 LICENSE AND COPYRIGHT

Copyright 2018 Konstantin S. Uvarin.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of namespace::local

