use strict;
use warnings;

use Test::More tests => 6;
use Test::Exception;

use Arena::Compact;

my $kx = Arena::Compact::key('x');
my $ky = Arena::Compact::key('y');

throws_ok { Arena::Compact::get('foo', $kx) } qr/node handle must be a reference/,
    "detected non-ref node handle";

throws_ok { Arena::Compact::get(\2, $kx) } qr/node handle has incorrect magic/,
    "detected bad ref node handle";

throws_ok { Arena::Compact::get(2) } qr/Usage/, "usage for bget / too few";
throws_ok { Arena::Compact::new(2) } qr/Usage/, "usage for bnew / too many";

my $x = Arena::Compact::new();

throws_ok { Arena::Compact::get($x, $ky) } qr/not found/, "noticed missing on get";
throws_ok { Arena::Compact::delete($x, $ky) } qr/not found/, "noticed missing on del";
