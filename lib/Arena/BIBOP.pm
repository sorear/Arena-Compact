#!/usr/bin/env perl
package Arena::BIBOP;
use strict;
use warnings;

BEGIN {

    require DynaLoader;

    our $VERSION = '0.01';

    our @ISA = ('DynaLoader');

    __PACKAGE__->bootstrap();

    *Arena::BIBOP::Node::put = *put;
    *Arena::BIBOP::Node::exists = *exists;
    *Arena::BIBOP::Node::delete = *delete;
    *Arena::BIBOP::Node::get = *get;

    undef @ISA; # namespace pollution FTL
}

1;

__END__

=head1 NAME

BIBOP - A space-efficient storage manager for Perl 5

=head1 SYNOPSIS

    use BIBOP;

    my $node = BIBOP::new();
    BIBOP::put($node, 'x', 'scalar' => 2);
    BIBOP::put($node, 'y', 'scalar' => 3);

    return BIBOP::get($node, 'x', 'scalar');

=head1 DESCRIPTION

In general, when Perl is faced with a tradeoff between saving time, saving
memory, and simplifying user code, memory efficiency gets the short end of the
stick.  This has mostly been a Good Thing, but occasionally you have an
unusually large dataset, and then what do you do?  This module exists for people
who want to save memory and time when working with large graph structures, at
the cost of some simplicity.  Unlike L<Storable>, it allows packed data to be
transparently converted into normal Perl data for operations.

The BIBOP heap is comprised of nodes.  At a high level, nodes resemble hashes;
they have identity (though they may not have stable names!), and they store a
set of fields, which can be accessed independantly.

Nodes are represented in Perl-space as scalars, a reference to which is passed
to the BIBOP API functions.  The scalars are blessed into BIBOP::Node as a
convenience, but BIBOP does not rely on this; class builders are expected to
use reblessed nodes as objects, and not inherit from BIBOP::Node.

=head1 PROCEDURAL INTERFACE

This is very low level, and has the advantage of not polluting namespaces.  It
is intended mostly for use in implementing object builders, such as
L<NooseX::BIBOP>.  No functions are exported.

=head2 BIBOP::new()

Creates a new, empty node.

=head2 BIBOP::get($node, $name, $type)

Fetches the value of a named field.  The type shall be as specified below,
and must match the set type exactly; no coercions are performed.

=head2 BIBOP::put($node, $name, $type, $value)

Sets the value of a named field.  The value must be convertable to the given
type.

=head1 SUPPORTED TYPES

Types in BIBOP are used primarily to control data representation, and as such
the object types are very coarse-grained.  They are B<not> intended to supplant
Moose type constraints.

=over 6

=item C<'scalar'>

A full Perl scalar field; it can contain any type of data, and can be made
magical using tie et al.  Carries a substantial memory cost.

=back

=head1 AUTHOR

Stefan O'Rear, C<< <stefanor@cox.net> >>

=head1 BUGS

No known bugs.

Please report any bugs through RT: email
C<bug-bibop at rt.cpan.org>, or browse
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=BIBOP>.

=head1 COPYRIGHT AND LICENSE

Copyright 2009 Stefan O'Rear.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

