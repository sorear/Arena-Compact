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

Arena::BIBOP - A space-efficient storage manager for Perl 5

=head1 SYNOPSIS

    use Arena::BIBOP;

    my $node = Arena::BIBOP::new();
    Arena::BIBOP::put($node, 'x', 'scalar' => 2);
    Arena::BIBOP::put($node, 'y', 'scalar' => 3);

    return Arena::BIBOP::get($node, 'x', 'scalar');

=head1 DESCRIPTION

In general, when Perl is faced with a tradeoff between saving time, saving
memory, and simplifying user code, memory efficiency gets the short end of the
stick.  This has mostly been a Good Thing, but occasionally you have an
unusually large dataset, and then what do you do?  This module exists for people
who want to save memory and time when working with large graph structures, at
the cost of some simplicity.  Unlike L<Storable>, it allows packed data to be
transparently converted into normal Perl data for operations.

The Arena::BIBOP heap is comprised of nodes.  At a high level, nodes resemble
hashes; they have identity (though they may not have stable names!), and they
store a set of fields, which can be accessed independantly.

Nodes are represented in Perl-space as scalars, a reference to which is passed
to the Arena::BIBOP API functions.  The scalars are blessed into
Arena::BIBOP::Node as a convenience, but Arena::BIBOP does not rely on this;
class builders are expected to use reblessed nodes as objects, and not inherit
from Arena::BIBOP::Node.

=head1 INTERFACE

This is very low level, and has the advantage of not polluting namespaces.  It
is intended mostly for use in implementing object builders, such as
L<NooseX::BIBOP>.  No functions are exported.

=head2 Arena::BIBOP::new()

Creates a new, empty node.

=head2 Arena::BIBOP::key('name'[, 'type'])

Return a key identifier for the given name and type.  If the type is not
specified, defaults to scalar.  (Types are not yet implemented and must be
omitted.)

=head2 BIBOP::get($node, $key)

Fetches the value of a named field.

=head2 BIBOP::put($node, $key, $value)

Sets the value of a named field.

=head1 AUTHOR

Stefan O'Rear, C<< <stefanor@cox.net> >>

=head1 BUGS

No known bugs.

Please report any bugs through RT: email
C<bug-arena-bibop at rt.cpan.org>, or browse
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Arena-BIBOP>.

=head1 COPYRIGHT AND LICENSE

Copyright 2009 Stefan O'Rear.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

