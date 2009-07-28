use strict;
use warnings;

use Test::More tests => 3;

use Arena::Compact -all => { -prefix => 'b' };

my $node = bnew();

ok(ref $node, "bnew returned something");
isa_ok($node, 'Arena::Compact::Node', "node is initially a Node");

undef $node;

pass("Node went out of scope OK");
