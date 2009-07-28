use strict;
use warnings;

use Test::More tests => 6;
use Test::Exception;

use Arena::Compact -all => { -prefix => 'b' };

my $kx = bkey('x');
my $ky = bkey('y');

throws_ok { bget('foo', $kx) } qr/node handle must be a reference/,
    "detected non-ref node handle";

throws_ok { bget(\2, $kx) } qr/node handle has incorrect magic/,
    "detected bad ref node handle";

throws_ok { bget(2) } qr/Usage/, "usage for bget / too few";
throws_ok { bnew(2) } qr/Usage/, "usage for bnew / too many";

my $x = bnew();

throws_ok { bget($x, $ky) } qr/not found/, "noticed missing on get";
throws_ok { bdelete($x, $ky) } qr/not found/, "noticed missing on del";
