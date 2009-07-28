use strict;
use warnings;

use Test::More tests => 3;

use Arena::Compact;

my $node = Arena::Compact::new();

ok(ref $node, "bnew returned something");
isa_ok($node, 'Arena::Compact::Node', "node is initially a Compact::Node");

undef $node;

pass("Node went out of scope OK");
