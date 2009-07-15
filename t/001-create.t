use strict;
use warnings;

use Test::More tests => 3;

use Arena::BIBOP;

my $node = Arena::BIBOP::bnew();

ok(ref $node, "bnew returned something");
isa_ok($node, 'Arena::BIBOP::Node', "node is initially a BIBOP::Node");

undef $node;

pass("Node went out of scope OK");
