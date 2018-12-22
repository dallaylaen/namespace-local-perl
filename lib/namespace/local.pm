use 5.008;
use strict;
use warnings FATAL => 'all';

package namespace::local;

our $VERSION = '0.08';

=head1 NAME

namespace::local - Confine imports or functions to a given scope

=head1 SYNOPSIS

This module allows to confine imports or private functions
to a given scope.

    package My::Module;

    sub normal_method {
        # frobnicate; # nope!
    };

    sub method_with_sugar {
        use namespace::local;
        use Crazy::Prototyped::DSL qw(do_this do_that frobnicate);

        do_this;
        do_that;
        frobnicate;
    };

    sub another_method {
        # frobnicate; # nope!
    };

The calling module's symbol table is saved at the C<use> line
and restored upon leaving the block.

The subsequent imports will do their job within the block,
but will not be available as methods at runtime.

=head1 MODES OF OPERATION

=head2 -around

This confines all subsequent imports and functions
between the use of L<namespace::local> and the end of scope.

    package My::Package;

    sub normal_sub {
        # frobnicate() is unknown
    }

    sub using_import {
        use namespace::local -around;
        use Some::Crazy::DSL qw(frobnicate);
        frobnicate Foo => 42;
    }

    sub no_import {
        # frobnicate() is unknown
    }

=head2 -below (the default)

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

=head2 -only => \@list

Only affect the listed symbols (with sigils).
Rules are the same as for -except.

=head2 -only => <regex>

Only affect symbols with matching names.

All C<-only> and C<-except> options act together, further restricting the
set of affected symbols.

=head1 EXEMPTIONS

The following symbols are not touched by this module, to avoid breaking things:

=over

=item * anything that does not consist of word characters;

=item * $_, @_, $1, $2, ...;

=item * Arrays: C<@CARP_NOT>, C<@EXPORT>, C<@EXPORT_OK>, C<@ISA>;

=item * Hashes: C<%OVERLOAD>;

=item * Files: C<DATA>, C<STDERR>, C<STDIN>, C<STDOUT>;

=item * Functions: C<AUTOLOAD>, C<DESTROY>, C<import>;

=item * Scalars: C<$AUTOLOAD>, C<$a>, C<$b>;

=back

This list is likely incomplete, and may grow in the future.

=head1 METHODS/FUNCTIONS

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

Up to v.0.07, C<-around> used to be the default mode instead of C<-below>.
C<-around> is much more restrictive, in particular, it prevents functions
defined below the block from propagating above the block.

This is less of a problem than imported functions leaking upward.
No perfect solution has yet been found.

=cut

use B::Hooks::EndOfScope 'on_scope_end';

my @stack;

sub import {
    my $class = shift;

    my $command = namespace::local::_command->new( caller => [ caller ] );
    $command->parse_options( @_ );

    # on_scope_end executes multiple callbacks as FIFO
    # we need reversed order, so use a stack of commands.
    $stack[-1]->set_next( $command ) if @stack;
    push @stack, $command;

    $command->prepare;

    on_scope_end {
        local $Carp::Internal{'B::Hooks::EndOfScope::XS'} = 1;
        local $Carp::Internal{'B::Hooks::EndOfScope'} = 1;
        pop @stack;
        $command->execute;
    };
};

=head1 ENVIRONMENT

Set C<PERL_NAMESPACE_LOCAL=debug> to see some debugging information
upon module load.

=head1 THE INTERNALS

A stack of "command" objects is used behind the scenes.

Its interface is not public, see this module's source.

Calling

=over

=item new

=back

on this package will create a command object,
I<not> a C<namespace::local> instance.

The creation and destruction of command has no effect on the namespaces.

Instead, special C<prepare> and C<execute> methods
are called upon import and leaving scope, respectively.

=cut

sub new {
    my $unused = shift;
    namespace::local::_command->new(caller => [caller 0], @_);
};

package
    namespace::local::_command;

# FIRST AND FOREMOST

# See C<perldoc perlmod> for how perl stores the Symbol Tables.

# In this module we use two-level hashrefs to represent the table:
# $table->{ $name }{ $type } = $reference
# where $name is a function/variable/whatever name,
# $type is one of ARRAY, CODE, FORMAT, HASH, IO, and SCALAR (see @TYPES below),
# and $reference is a reference of corresponding type (or undef).

# So Foo::bar() would be represented as $table->{foo}{CODE}
# whereas @Foo::ISA is $table->{ISA}{ARRAY}.

use Carp;
use Scalar::Util qw(blessed refaddr reftype);
our @CARP_NOT = qw(namespace::local);

# TODO need better env parsing...
use constant DEBUG => ( lc ($ENV{PERL_NAMESPACE_LOCAL} || '' ) eq 'debug' ? 1 : 0 );

### Setup methods

sub new {
    my ($class, %opt) = @_;

    # TODO check options
    $opt{caller}     ||= [ caller 0 ];
    $opt{except_rex} ||= qr/^[0-9]+$|^_$/; # no matter what, exempt $_, $1, ...
    $opt{only_rex}   ||= qr/^/; # match all
    $opt{action}     ||= '-below';
    $opt{target}     ||= $opt{caller}[0];
    $opt{origin}     ||= join ":", @{$opt{caller}}[1,2];

    # Skip some well-known variables and functions
    # Format: touch_not{ $name }{ $type }
    # NOTE if you change the list, also change the EXEMPTIONS section in the POD.
    $opt{touch_not}{$_}{ARRAY}++  for qw( CARP_NOT EXPORT EXPORT_OK ISA );
    $opt{touch_not}{$_}{CODE}++   for qw( AUTOLOAD DESTROY import );
    $opt{touch_not}{$_}{HASH}++   for qw( OVERLOAD );
    $opt{touch_not}{$_}{IO}++     for qw( DATA STDERR STDIN STDOUT );
    $opt{touch_not}{$_}{SCALAR}++ for qw( AUTOLOAD a b );

    return bless \%opt, $class;
};

sub set_next {
    my ($self, $next) = @_;

    carp "probably a bug in namespace::local - uncommitted command replaced in chain"
        if $self->{next} and !$self->{next}{done};

    $self->{next} = $next;
};

sub DESTROY {
    my $self = shift;
    carp "probably a bug in namespace::local: callback set at $self->{origin} but never executed"
        if $self->{todo} and !$self->{done};
};

my %known_action;
$known_action{$_}++ for qw(-above -below -around);

# This changes nothing except the object itself
# input is the same as that of namespace::local->import
sub parse_options {
    my $self = shift;

    # wrote a Getopt::Long from scratch...
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
        } elsif ($arg eq '-only') {
            my $cond = shift;
            if (ref $cond eq 'Regexp') {
                $self->{only_rex} = $cond;
            } elsif (ref $cond eq 'ARRAY') {
                $self->restrict( @$cond );
            } else {
                _croak( "-only argument must be regexp or array" )
            };
        } else {
            _croak( "unknown option $arg" );
        };
    };
};

sub touch_not {
    my ($self, @list) = @_;

    foreach (sigil_to_type(@list)) {
        $self->{touch_not}{ $_->[0] }{ $_->[1] }++
    };
};

sub restrict {
    my ($self, @list) = @_;

    foreach (sigil_to_type(@list)) {
        $self->{restrict_symbols}{ $_->[0] }{ $_->[1] }++
    };
};

# TODO join with @TYPES array from below
my %sigil = (
    ''  => 'CODE',
    '$' => 'SCALAR',
    '%' => 'HASH',
    '@' => 'ARRAY',
);

# returns [ name, type ] for each argument
sub sigil_to_type {
    map {
        /^([\$\@\%]?)(\w+)$/
            or _croak( "cannot exempt sybmol $_: unsupported format" );
        [ $2, $sigil{$1} ]
    } @_;
};

### Command pattern split into prepare + execute

# input: none
# output: none
# side effects: modify target package + setup callback for self->execute
sub prepare {
    my $self = shift;

    my $action = $self->{action};

    my $table = $self->read_symbols;

    if ($action eq '-around') {
        # Overwrite symbol table with a copy of itself.
        # Somehow this triggers binding of symbols in the code
        #    that was parsed so far (i.e. above the 'use' line)
        #    and undefined symbols (in that area) remain so forever
        $self->write_symbols( $table );
    } elsif ( $action eq '-below' ) {
        # Stabilize known functions, leave everything else as is
        my $func = $self->filter_functions( $table );
        $self->write_symbols( $func );
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

# input: none
# output: none
# side effect: modify target package
sub execute {
    my ($self) = @_;

    # always execute stacked commands in reverse order
    $self->{next}->execute
        if $self->{next};

    $self->{todo}->()
        unless $self->{done}++;
};

### High-level effectful functions

# Don't ever touch NAME, PACKAGE, and GLOB that are also known to Perl
my @TYPES = qw(SCALAR ARRAY HASH CODE IO FORMAT);

# In: symbol table hashref
# Out: side effect
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

    $clear_list ||= [ $self->read_names ];
    $table ||= {};

    my %uniq;
    $uniq{$_}++ for keys %$table, @$clear_list;

    # re-read the symbol table
    my $old_table = $self->read_symbols( [ keys %uniq ] );

    # create a plan for change
    my $diff = $self->table_diff( $old_table, $table );
    return unless keys %$diff;

    $self->write_symbols( $diff );
};

sub filter_functions {
    my ($self, $table) = @_;

    my %new_table;

    foreach (keys %$table) {
        $new_table{$_} = $table->{$_}
            if defined $table->{$_}{CODE};
    };

    return \%new_table;
};

# Oddly enough, pure
# In: old and new two symbol table hashrefs
# Out: part of new table that differs from the old,
#      with touch_not rules applied
sub table_diff {
    my ($self, $old_table, $new_table) = @_;

    my %uniq_name;
    $uniq_name{$_}++ for keys %$old_table, keys %$new_table;

    my $touch_not = $self->{touch_not};

    if (my $restrict = $self->{restrict_symbols}) {
        # If a restriction is in place, invert it and merge into skip
        # TODO write this better
        # TODO does it really belong here?
        $restrict->{$_} or delete $uniq_name{$_} for keys %uniq_name;
        my %real_touch_not;
        foreach my $name (keys %uniq_name) {
            # 2 levels of shallow copy is enough
            foreach my $type( @TYPES ) {
                $real_touch_not{$name}{$type}++
                    unless $restrict->{$name}{$type} and not $touch_not->{$name}{$type};
            };
        };
        $touch_not = \%real_touch_not;
    };

    my $diff;

    # iterate over keys of both, 2 levels deep
    foreach my $name (sort keys %uniq_name) {
        my $old  = $old_table->{$name} || {};
        my $new  = $new_table->{$name} || {};
        my $skip = $touch_not->{$name} || {};

        my %uniq_type;
        $uniq_type{$_}++ for keys %$old, keys %$new;

        foreach my $type (sort keys %uniq_type) {
            next if $skip->{$type};

            if (ref $old->{$type} ne ref $new->{$type}) {
                # As nonrefs are not allowed here,
                # this also handles undef vs. defined case
                $diff->{$name}{$type} = $new->{$type};
                next;
            };

            # both undef, nothing to see here
            next unless ref $new->{$type};

            # pointing to different things
            if (refaddr $old->{$type} != refaddr $new->{$type}) {
                $diff->{$name}{$type} = $new->{$type};
                next;
            };
        };

        if ($diff->{$name}) {
            # if we cannot avoid overwriting,
            # make sure to copy ALL skipped values we know of
            $diff->{$name}{$_} = $old->{$_} for keys %$skip;

            # removing a scalar copletely didn't work very well on Perl 5.10.1,
            # causing segfaults in unrelated places.
            $diff->{$name}{SCALAR} ||= \undef;
        };
    };

    return $diff;
};

### Low-level symbol-table read & write
### no magic should happen above this line

# NOTE that even here we are in full strict mode
# The pattern for working with raw data is this:
# my $value = do { no strict 'refs'; ... }; ## no critic

# in: none
# out: sorted & filtered list of symbols
sub read_names {
    my $self = shift;

    my $package = $self->{target};
    my $except  = $self->{except_rex};
    my $only    = $self->{only_rex};

    my @list = sort grep {
        /^\w+$/ and $_ !~ $except and $_ =~ $only
    } do {
        no strict 'refs'; ## no critic
        keys %{ $package."::" };
    };

    return @list;
};

# In: symbol list arrayref (read_symbols if none)
# Out: symbol table hashref
sub read_symbols {
    my ($self, $list) = @_;

    my $package = $self->{target};
    $list ||= [ $self->read_names ];
    $list = [ grep { $self->{restrict_symbols}{$_} } @$list ]
        if $self->{restrict_symbols};

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

# writes raw symbols, ignoring touch_not!
# In: symbol table hashref
# Out: none
sub write_symbols {
    my ($self, $table) = @_;

    my $package = $self->{target};

    if (DEBUG) {
        my $old_table = $self->read_symbols;
        $self->message( "package $self->{target} to be altered: ".dump_table($table, $old_table) )
    };


    foreach my $name( keys %$table ) {
        my $copy = $table->{$name};

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
                carp "namespace::local: failed to write $package :: $name ($type), but trying to continue: $@";
            };
        };
    };
};

### Logging

sub dump_table {
    my ($table, $old_table) = @_;

    my @out;
    foreach my $name( sort keys %$table ) {
        my $glob = $table->{$name};
        foreach my $type( sort keys %$glob ) {
            push @out, "*$name\{$type\}=".(
                $old_table
                    ? _is_and_was( $glob->{$type}, $old_table->{$name}{$type} )
                    : _ref2str( $glob->{$type} )
            );
        };
    };

    return join ", ", @out;
};

sub _is_and_was {
    my ($new, $old) = @_;

    if ((refaddr $new || 0) != (refaddr $old || 0)) {
        return _ref2str( $new )."[was: "._ref2str( $old )."]";
    } else {
        return _ref2str( $new )."[unchanged]";
    };
};

# TODO find existing?
sub _ref2str {
    my $ref = shift;

    return ref $ref
        ? blessed $ref
            ? sprintf "%s=%s(0x%x)", ref $ref, reftype $ref, refaddr $ref
            : sprintf "%s(0x%x)", ref $ref, refaddr $ref
        : 'undef';
};

sub message {
    my ($self, $msg) = @_;

    $msg =~ s/\n$//s;
    carp "$msg via namespace::local from $self->{origin}";
};

sub _croak {
    croak ("namespace::local: ".shift);
};

=head1 BUGS

As of 0.0604, C<-around> hides subroutines defined below its scope end
from anything above it.
No solution exists so far.

This is experimental module. There certainly are more bugs.

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

L<namespace::clean> gave the inspiration for this module.

L<namespace::sweep>, L<namespace::autoclean> and probably more also clean
caller's namespace, but differently.

L<B::Hooks::EndOfScope> is used as a backend.

L<perlmod/Symbol Tables> explains how reading/writing the namespace works.

=head1 LICENSE AND COPYRIGHT

Copyright 2018 Konstantin S. Uvarin, C<< <khedin at gmail.com> >>

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

