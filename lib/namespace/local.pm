use 5.008;
use strict;
use warnings FATAL => 'all';

package namespace::local;

our $VERSION = '0.0603';

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

=head2 -target => Package::Name

Act on another package instead of the caller.
Note that L<namespace::local> is only meant to be used in BEGIN phase.

=head2 -except => \@list

Exempt symbols mentioned in list (with sigils)
from the module's action.

No sigil means a function.
Only names made of word characters are supported.

=head2 -except => <regex>

Exempt symbols with names matching the regular expression
from the module's action.

Note that sigils are ignored here.

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

my $last_command;

sub import {
    my $class = shift;

    my $command = namespace::local::_command->new( target => scalar caller );
    $command->parse_options( @_ );

    # on_scope_end callback execution order is direct
    # we need reversed order, so use a stack of commands.
    $last_command->set_next( $command ) if $last_command;
    $last_command = $command;
    weaken $last_command; # to avoid leaks

    $command->prepare;

    on_scope_end {
        $command->execute;
    };
};

;

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
    $opt{action} = '-around';

    # Skip some well-known variables and functions
    # Format: touch_not{ $name }{ $type }
    # NOTE if you change the list, also change the EXEMPTIONS section in the POD.
    $opt{touch_not}{$_}{ARRAY}++  for qw( CARP_NOT EXPORT EXPORT_OK ISA );
    $opt{touch_not}{$_}{CODE}++   for qw( AUTOLOAD DESTROY import );
    $opt{touch_not}{$_}{IO}++     for qw( DATA STDERR STDIN STDOUT );
    $opt{touch_not}{$_}{SCALAR}++ for qw( AUTOLOAD a b );

    return bless \%opt, $class;
};

sub set_next {
    my ($self, $next) = @_;
    $self->{next} = $next;
};

my %known_action;
$known_action{$_}++ for qw(-above -below -around);

# this changes nothing except the object itself
sub parse_options {
    my $self = shift;

    while (@_) {
        my $arg = shift;
        if ( $known_action{$arg} ) {
            $self->{action} = $arg;
        } elsif ($arg eq '-target') {
            $self->{target} = shift;
        } elsif ($arg eq '-except') {
            my $cond = shift;
            if (ref $cond eq 'Regexp') {
                $self->{except_rex} = qr((?:$self->{except_rex})|(?:$cond));
            } elsif (ref $cond eq 'ARRAY') {
                $self->touch_not( @$cond );
            } else {
                _croak( "-except argument must be regexp or array" )
            };
        } else {
            _croak( "unknown option $arg" );
        };
    };
};

# TODO join with @TYPE array from below
my %sigil = (
    ''  => 'CODE',
    '$' => 'SCALAR',
    '%' => 'HASH',
    '@' => 'ARRAY',
);

sub touch_not {
    my ($self, @list) = @_;

    foreach (@list) {
        /^([\$\@\%]?)(\w+)$/
            or _croak( "cannot exempt sybmol $_: unsupported format" );
        $self->{touch_not}{$2}{ $sigil{$1} }++
    };
};

# side effects + setup self->execute
sub prepare {
    my $self = shift;

    my $action = $self->{action};

    my $table = $self->read_symbols;

    # FIXME UGLY HACK
    # Immediate backup-and-restore of symbol table
    #     somehow forces binding of symbols
    #     above 'use namespace::local' line
    #     thus preventing subsequent imports from leaking upwards
    # I do not know why it works, it shouldn't.
    if ($action eq '-around') {
        $self->replace_symbols( undef, $table );
    };

    if ($action eq '-above' ) {
        $self->{todo} = sub {
            $self->erase_only_symbols( $table );
        };
    } else {
        $self->{todo} = sub {
            $self->replace_symbols( undef, $table );
        };
    };
};

sub execute {
    my ($self) = @_;

    # always execute stacked commands in reverse order
    $self->{next}->execute
        if $self->{next};

    $self->{todo}->()
        unless $self->{done}++;
};

# Don't touch NAME, PACKAGE, and GLOB itself
my @TYPES = qw(SCALAR ARRAY HASH CODE IO FORMAT);

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

sub erase_only_symbols {
    my ($self, $table) = @_;

    my $package = $self->{target};
    my @list = keys %$table;

    # load all necessary symbols
    my $current = $self->read_symbols( \@list );

    # filter out what we were going to delete
    foreach my $name ( @list ) {
        $table->{$name}{$_} and delete $current->{$name}{$_}
            for @TYPES;
    };

    # put it back in place
    $self->replace_symbols( \@list, $current );
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

# This method's signature is a bit counterintuitive:
# $self->replace_symbols( \@names_to_erase, \%new_table_entries )
# If first argument is omitted, the whole namespace is scanned instead.
# Separate erase_symbols and write_symbols turned out to be cumbersome
#    because of the need to handle granular exclusion list.
# This method can fill both roles.
# Providing an empty list would make it just write the symbol table,
#    whereas an empty hash would mean deletion only.
sub replace_symbols {
    my ($self, $clear_list, $table) = @_;

    my $package = $self->{target};

    $clear_list ||= [ $self->read_names ];
    $table ||= {};

    my %uniq;
    $uniq{$_}++ for keys %$table, @$clear_list;

    foreach my $name( keys %uniq ) {
        my $copy = $table->{$name} || {};
        if ( my $skip = $self->{touch_not}{$name} ) {
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

        foreach my $type ( keys %$copy ) {
            ref $copy->{$type} or next;
            eval {
                # FIXME on perls 5.014..5.022 this block fails
                # because @ISA is readonly.
                # So we wrap it in eval with no catch
                # until a better solution is done
                no strict 'refs'; ## no critic
                *{ $package."::".$name } = $copy->{$type};
                1;
            } || do {
                Carp::cluck "namespace::local: working around error: $@";
            };
        };
    };
};

sub _croak {
    croak ("namespace::local: ".shift);
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

